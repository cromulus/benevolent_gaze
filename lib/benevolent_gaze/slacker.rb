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

      #if from == channel, it is a user responding to marco, send to kiosk
      #if @marco, check for commands
      # command: who-> r.hgetall "current_devices"
      # command: @username -> check redis for device
      client.on :presence_change do |data|
        case data["presence"]
        when "active"
          r.sadd("current_slackers",data['user'])
        when "away"
          r.srem("current_slackers",data['user'])
        end
      end

      client.on :message do |data|
        puts "channel=#{data['channel']}, user=#{data['user']}"
        if data['channel'] == "D0LGR7LJE"
          puts "post '#{data['text']}' to kiosk from #{data['user']}"
          user = data['user']
          msg  = data['text']
          r.publish("slackback",{user:user,msg:msg,data: data}.to_json)
          client.message channel: "#{data['channel']}", text:"sent '#{msg}' to the kiosk"
        elsif data['text'].match(/<@U0L4P1CSH>/)
          msg = data['text'].gsub(/<@U0L4P1CSH> /,"")
          case msg
          when /^help/
            client.message channel: "#{data['channel']}", text:" `@marco @username` checks if they are in the office, `@marco who` lists all people in the office. If you get a message from marco, your responses to that message will be posted to the board."
          when /^who|list/
            client.message channel: "#{data['channel']}", text:"Currently in the office:"
            r.hgetall("current_devices").each do |k,v|
              slack = r.get("slack_id:#{k}") || false
              puts slack
              puts data['channel']
              next unless slack
              client.message channel: "#{data['channel']}", text:"<@"+ slack +">"
            end

          when /<@([^>]+)>/
            user = $1
            device_name = nil
            r.keys("slack_id:*").each{|s| device_name = s if r.get(s)==user }
            if device_name
              client.message channel: "#{data['channel']}", text: "Polo"
            else
              client.message channel: "#{data['channel']}", text: "*Cricket*"
            end
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
