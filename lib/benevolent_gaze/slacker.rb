require 'json'
require 'redis'
require 'slack-ruby-client'
require 'celluloid'
require 'celluloid/io'
Slack.configure do |config|
  config.token = ENV['SLACK_API_TOKEN']
end

module BenevolentGaze
  class Slacker
    def self.run!
      r = Redis.new
      client = Slack::RealTime::Client.new(websocket_ping: 60)

      ###################################################
      # What we want to do:
      ###################################################

      # if from == channel, it is a user responding to marco, send to kiosk
      # if @marco, check for commands
      # command: who-> r.hgetall "current_devices"
      # command: @username -> check redis for device
      client.on :presence_change do |data|
        puts "user #{data['user']} is #{data['presence']}"
        case data['presence']
        when 'active'
          r.sadd('current_slackers', data['user'])
          # if we haven't invited them AND they aren't registered...
          # invite them!
          if !r.sismember('slinvited',data['user']) && r.hget('slack_id2slack_name', data['user']).nil?
            puts "inviting #{data['user']}"
            client.web_client.chat_postMessage(channel: data['user'],
                                    text: "Hi! Welcome! If you want to be on the reception Kiosk, click on this link http://150.brl.nyc/slack_me_up/#{data['user']} when you are in the office, connected to the wifi. (It won't work anywhere else.)",
                                    as_user: true)
            r.sadd('slinvited',data['user'])
          end
        when 'away'
          r.srem('current_slackers', data['user'])
        end
      end

      client.on :message do |data|
        # responses to the bot's own channel
        if client.ims.keys.include?(data['channel']) && data['user'] != 'U0L4P1CSH'
          puts "post '#{data['text']}' to kiosk from #{data['user']}"
          user = data['user']
          msg  = data['text']
          r.lpush('slackback', { user: user, msg: msg, data: data }.to_json)
          client.message channel: (data['channel']).to_s, text: "sent '#{msg}' to the kiosk"
        elsif data['text'] =~ /<@U0L4P1CSH>/
          puts "channel=#{data['channel']}, user=#{data['user']} msg=#{data['text']}"
          msg = data['text'].gsub(/<@U0L4P1CSH>/, '').delete(':').lstrip
          case msg
          when /^help/
            client.message channel: (data['channel']).to_s, text: '`@marco @username` checks if they are in the office, `@marco who` lists all people in the office. If you get a message from marco, your responses to that message will be posted to the board. Register here: http://150.brl.nyc/'
          when /^who|list/

            names = []
            r.hgetall('current_devices').each do |device, real_name|
              slack = r.get("slack:#{device}") || false
              next unless slack
              name = real_name.empty? ? slack : real_name
              names << name
            end
            client.message channel: (data['channel']).to_s, text: "Currently in the office: #{names.join('
            ')}
Register your devices here: http://150.brl.nyc/"
          when /<@([^>]+)>/
            user = Regexp.last_match(1)

            online = false
            unknown = true
            r.keys('slack_id:*').each do |device|
              next if online == true
              if r.get(device) == user
                unknown = false
                online = r.hexists('current_devices', device.split(':').last)
              end
            end

            if online
              client.message channel: (data['channel']).to_s, text: 'Polo (they are in the office, I think)'
            elsif unknown
              client.message channel: (data['channel']).to_s, text: "I don't know who you are talking about. Ask <@#{user}> to register here: http://150.brl.nyc/"
            else
              client.message channel: (data['channel']).to_s, text: 'Not Here... Womp-whaaaaa.....'
            end
          else
            client.message channel: (data['channel']).to_s, text: "
              I didn't understand that.... I'm just a robot... `@marco @username` checks if they are in the office, `@marco who` lists all people in the office. If you get a message from @marco, your responses to that message will be posted to the board.Register your devices here: http://150.brl.nyc/"
          end
        end
      end

      client.start!
    end

    class << self
      # where our methods go that implement our things
    end
  end
end
