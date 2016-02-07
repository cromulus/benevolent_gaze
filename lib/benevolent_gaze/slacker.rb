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
      client.on :hello do
        puts "Successfully connected, welcome '#{client.self['name']}' to the '#{client.team['name']}' team at https://#{client.team['domain']}.slack.com."
      end

      client.on :message do |data|
        #client.message channel: "#bot-testing", text:"Hi <@#{data'user']}>! #{data['text']}"
        puts data['text']
        case data['text']
        when 'bot hi' then
          client.message channel: "#{data['channel']}", text: "Hi <@#{data.user}>!"
        when /^bot/ then
          client.message channel: "#{data['channel']}", text: "Sorry <@#{data.user}>, what?"
        end
      end

      client.start!
    end

    class << self
      # where our methods go!
    end
  end
end