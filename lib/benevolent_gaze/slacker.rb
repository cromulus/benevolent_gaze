require 'json'
require 'redis'
require 'slack-ruby-client'
require 'celluloid'
require 'celluloid/io'
Slack.configure do |config|
  #config.token =  "xoxp-12422969797-12427127041-20531002689-15f0cd6035" #ENV['SLACK_API_TOKEN']
  config.token = "xoxb-20159046901-w2V7crilpVg7Uxcr5fpFMdxl"
end

module BenevolentGaze
  class Slacker
    def self.run!
      client = Slack::RealTime::Client.new(websocket_ping: 60)

      ###################################################
      # What we want to do:
      ###################################################

      #if from == channel, it is a user responding to marco, send to kiosk
      #if @marco, check for commands
      # command: who-> r.hgetall "current_devices"
      # command: @username -> check redis for device
      client.on :message do |data|
        puts "channel=#{data['channel']}, user=#{data['user']}"
        if data['channel'] == "D0LGR7LJE"
          puts "post #{data['text']} to kiosk"
          client.message channel: "#{data['channel']}", text:"sending message to kiosk not implemented yet"
        elsif data['text'].match(/<@U0L4P1CSH>/)
          msg = data['text'].gsub(/<@U0L4P1CSH> /,"")
          case msg
          when /^help/
            client.message channel: "#{data['channel']}", text:" `@marco @username` checks if they are in the office, `@marco who` lists all people in the office. If you get a message from marco, your responses to that message will be posted to the board."
          when /^who/ || /^list/
            client.message channel: "#{data['channel']}", text:" who is in the office is not implemented"
          when /<@([^>]+)>/

            client.message channel: "#{data['channel']}", text:"user lookup not implemented. <@#{$1}>"
          end
        end

      end

      client.start!
    end

    class << self
      # where our methods go!
    end
  end
end