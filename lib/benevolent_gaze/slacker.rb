require 'json'
require 'redis'
require 'slack-ruby-bot'
require 'httparty'
require 'celluloid'
require 'celluloid/io'

# https://github.com/slack-ruby/slack-ruby-bot/blob/master/examples/weather/weatherbot.rb

# use https://github.com/slack-ruby/slack-ruby-bot
Slack.configure do |config|
  config.token = ENV['SLACK_API_TOKEN']
end

###################################################
# What we want to do:
###################################################

# if from == channel, it is a user responding to marco, send to kiosk
# if @marco, check for commands
# command: who-> r.hgetall "current_devices"
# command: @username -> check redis for device

SlackRubyBot::Client.logger.level = Logger::WARN

module BenevolentGaze
  class Slacker < SlackRubyBot::Bot
    def initialize
      @redis = Redis.new()
      @r = @redis
    end

    help do
      title 'Marco Polo'
      desc 'This bot tells you who is in the office.'

      command 'who' do
        desc 'who is at 150 court st.'
      end

      command '@username?' do
        desc 'Tells you if @username is in the office.'
        long_desc "thats about it"
      end
    end

  end
end

module BenevolentGaze
  module Commands
    class Default < SlackRubyBot::Commands::Base

      command 'call' do |client, data, match|
        post_to_kiosk(client,data)
      end
      command 'marco' do |client, data, match|
        post_to_kiosk(client,data)
      end

      command 'ping' do |client, data, match|
        client.say(text: 'pong', channel: data.channel)
      end

      command 'who','list' do |client,data,command|
        names = []
        r = Redis.new
        r.hgetall('current_devices').each do |device, real_name|
          slack = r.get("slack:#{device}") || false
          next unless slack
          name = real_name.empty? ? slack : real_name
          names << name
        end
        names.uniq!
        client.message channel: (data['channel']).to_s, text: "Currently in the office: #{names.join('
        ')}
        Register your devices here: http://150.brl.nyc/"
      end

      scan(/<@([^>]+)>/) do |client,data,users|
        online = false
        unknown = true
        if users[1] # the second user is the one we're looking for
          user = users[1][0]

          r = Redis.new
          r.keys('slack_id:*').each do |device|
            next if online == true
            if r.get(device) == user
              unknown = false
              online = r.hexists('current_devices', device.split(':').last)
            end
          end

          if online
            client.message channel: (data['channel']).to_s, text: "Polo (<@#{user}> is in the office, I think)"
          elsif unknown
            client.message channel: (data['channel']).to_s, text: "I don't know who you are talking about. Ask <@#{user}> to register here: http://150.brl.nyc/"
          else
            client.message channel: (data['channel']).to_s, text: 'Not Here... Womp-whaaaaa.....'
          end
        end
      end

      private

      def post_to_kiosk(data,client)
        if client.ims.keys.include?(data['channel']) && data['user'] != 'U0L4P1CSH'
          puts "post '#{data['text']}' to kiosk from #{data['user']}"
          user = data['user']
          msg  = data['text']
          slack_msg = { user: user, msg: msg, data: data }.to_json

          HTTParty.post("http://#{ENV['SERVER_HOST']}:#{ENV['IPORT']}/msg",
                        query: { msg: slack_msg })

          client.message channel: (data['channel']).to_s, text: "sent '#{msg}' to the kiosk"
        end
      end
    end
  end
end

module BenevolentGaze
  class Server < SlackRubyBot::Server

    on 'hello' do |client, data|
      puts "Successfully connected, welcome '#{client.self.name}' to the '#{client.team.name}' team at https://#{client.team.domain}.slack.com."
    end

    on 'presence_change' do |client,data|
      r = Redis.new()
      puts "user #{data['user']} is #{data['presence']}"
      case data['presence']
      when 'active'

        r.sadd('current_slackers', data['user'])
        # if we haven't invited them AND they aren't registered...
        # invite them!
        if !r.sismember('slinvited', data['user']) && r.hget('slack_id2slack_name', data['user']).nil?
          puts "inviting #{data['user']}"
          client.web_client.chat_postMessage(channel: data['user'],
                                             text: "Hi! Welcome! If you want to be on the reception Kiosk, click on this link http://150.brl.nyc/slack_me_up/#{data['user']} when you are in the office, connected to the wifi. (It won't work anywhere else.)",
                                             as_user: true)
          r.sadd('slinvited', data['user'])
        end
      when 'away'
        r.srem('current_slackers', data['user'])
      end
    end
  end
end
