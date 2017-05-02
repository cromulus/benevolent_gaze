require 'json'
require 'redis'
require 'slack-ruby-bot'
require 'httparty'
require 'celluloid'
require 'celluloid/io'
require 'google/cloud/vision'

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
      @redis = Redis.new
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
        long_desc 'thats about it'
      end
    end
  end
end

module BenevolentGaze
  module Commands
    class Default < SlackRubyBot::Commands::Base
      command 'ping' do |client, data, _match|
        client.say(text: 'pong', channel: data.channel)
      end

      command 'invite' do |client, data, users|
        message = data['message']
        users = message.scan(/<@([^>]+)>/)
        users = users.blank? ? data['user'] : users
        users.each do |user|
          client.web_client.chat_postMessage(channel: user,
                                             text: "Hi! Welcome! If you want to be on the reception Kiosk, click on this link http://#{ENV['SERVER_HOST']}/slack_me_up/#{user} when you are in the office, connected to the wifi. (It won't work anywhere else.)",
                                             as_user: true)
        end
      end

      command 'who', 'list' do |client, data, _command|
        names = []
        @r ||= Redis.current
        @r.hgetall('current_devices').each do |device, real_name|
          slack = @r.get("slack:#{device}") || false
          next unless slack
          name = real_name.empty? ? slack : real_name
          names << name
        end
        names.uniq!
        client.message(channel: (data['channel']).to_s, text: "Currently in the office:
        #{names.join("
        ")}
        Register your devices here: http://#{ENV['SERVER_HOST']}/register")
      end

      # scan(/<@([^>]+)>/) do |client, data, users|
      #   online = false
      #   unknown = true
      #   if users[1] # the second user is the one we're looking for
      #     user = users[1][0]

      #     r = Redis.new
      #     r.keys('slack_id:*').each do |device|
      #       next if online == true
      #       if r.get(device) == user
      #         unknown = false
      #         online = r.hexists('current_devices', device.split(':').last)
      #       end
      #     end

      #     if online
      #       client.message channel: (data['channel']).to_s, text: "Polo (<@#{user}> is in the office, I think)"
      #     elsif unknown
      #       client.message channel: (data['channel']).to_s, text: "I don't know who you are talking about. Ask <@#{user}> to register here: http://#{ENV['SERVER_HOST']}/register"
      #     else
      #       client.message channel: (data['channel']).to_s, text: 'Not Here... Womp-whaaaaa.....'
      #     end
      #   end
      # end

      # unsure about this one.
      command 'marco', 'call' do |client, data, _match|
        if client.ims.keys.include?(data['channel']) && data['user'] != 'U0L4P1CSH'
          puts "post '#{data['text']}' to kiosk from #{data['user']}"
          user = data['user']
          msg  = data['text']
          slack_msg = { user: user, msg: msg, data: data }.to_json

          # this should be over a redis pubsub, but I can't get it to work.
          HTTParty.post("http://#{ENV['SERVER_HOST']}:#{ENV['IPORT']}/msg",
                        query: { msg: slack_msg, msg_token: ENV['MSG_TOKEN'] })

          client.message(channel: (data['channel']).to_s,
                         text: "sent '#{msg}' to the kiosk")
        else
          client.message(channel: data.channel,
                         text: "Sorry <@#{data.user}>, I don't understand that command!",
                         gif: 'idiot')
        end
      end

      # catchall
      match(/^(?<bot>\w*)\s(?<expression>.*)$/) do |client, data, match|
        expression = match['expression'].strip
        next if expression == 1
        if client.ims.keys.include?(data['channel']) && data['user'] != 'U0L4P1CSH'
          puts "post '#{data['text']}' to kiosk from #{data['user']}"
          user = data['user']
          msg  = data['text']
          slack_msg = { user: user, msg: msg, data: data }.to_json

          # this should be over a redis pubsub, but I can't get it to work.
          HTTParty.post("http://#{ENV['SERVER_HOST']}:#{ENV['IPORT']}/msg",
                        query: { msg: slack_msg,
                          msg_token: ENV['MSG_TOKEN'] })

          client.message(channel: (data['channel']).to_s,
                         text: "sent '#{msg}' to the kiosk")
        end
      end
    end
  end
end

module BenevolentGaze
  class Server < SlackRubyBot::Server
    on 'hello' do |client, _data|
      puts "Successfully connected, welcome '#{client.self.name}' to the '#{client.team.name}' team at https://#{client.team.domain}.slack.com."
    end

    on 'presence_change' do |client, data|


      @r ||= Redis.current
      puts "#{data['user']}: is #{data['presence']}."
      case data['presence']
      when 'active'
        @r.sadd('current_slackers', data['user'])

        info = client.web_client.users_info(user: data['user'])
        user_data = info.user
        next if user_data.is_bot

        if user_data.profile.title == '' || user_data.profile.title.nil?
          if @r.get("profile_remind:#{data['user']}").nil?
            puts "no profile: #{data['user']}"
            client.web_client.chat_postMessage(channel: data['user'],
                                               text: 'Please update your profile so people know who you are!',
                                               as_user: true)
            # slightly less than once a day
            @r.setex("profile_remind:#{data['user']}", 60 * 59 * 24, true)
          end
        end

        facecheck = @r.get("face:#{data['user']}")
        if facecheck.nil? && !ENV['GOOGLE_PROJECT_ID'].nil?
          one_day = (60 * 60 * 24 )
          @vision ||= Google::Cloud::Vision.new project: ENV['GOOGLE_PROJECT_ID']
          image = @vision.image user_data.profile.image_512
          if image.faces.size == 1
            # don't check for a month. we have max 1k per month free
            @r.setex("face:#{data['user']}", one_day * 30 ,true)
          else
            # they changed it or wait one day check again. 1 day
            @r.setex("face:#{data['user']}", true, one_day)
            if @r.get("face_remind:#{data['user']}").nil?
              puts "no face: #{data['user']}"
              client.web_client.chat_postMessage(channel: data['user'],
                                                 text: 'Please update your Slack profile picture with a photo of your face so people can put a face to the name!',
                                                 as_user: true)

              @r.setex("face_remind:#{data['user']}", one_day - 60, true)
            end
          end
        end
        # if .includes("avatars/ava_")
        # go get the image, if it resolves to *.wp.com it's a broken avatar.
        # end
        #
        # if we haven't invited them AND they aren't registered...
        # invite them!
        if !@r.sismember('slinvited', data['user']) && @r.hget('slack_id2slack_name', data['user']).nil?
          puts "inviting #{data['user']}"
          client.web_client.chat_postMessage(channel: data['user'],
            text: "Hi! Welcome! If you want to be on the reception Kiosk, click on this link http://#{ENV['SERVER_HOST']}/slack_me_up/#{data['user']} when you are in the office, connected to the wifi. (It won't work anywhere else.)",
                                             as_user: true)
          @r.sadd('slinvited', data['user'])
        end
      when 'away'
        @r.srem('current_slackers', data['user'])
      end
    end
  end
end
