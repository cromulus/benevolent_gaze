require 'json'
require 'sinatra/base'
require 'sinatra/support'
require 'sinatra/json'
require 'redis'
require 'resolv'
require 'sinatra/cross_origin'
require 'aws/s3'
require 'securerandom'
require 'mini_magick'
require 'httparty'
require 'slack-ruby-client'
require "sinatra/reloader"

Encoding.default_external = 'utf-8'  if defined?(::Encoding)
ENV['AWS_ACCESS_KEY_ID']='AKIAIFUSUPNDXREX5Q7A'
ENV['AWS_CDN_BUCKET']='benevolentgazebucket'
ENV['AWS_SECRET_ACCESS_KEY']='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'
ENV['BG_COMPANY_URL']='http://www.happyfuncorp.com/register'

ENV['IPORT']='4567'
ENV['PORT']='4567'
ENV['IGNORE_HOSTS']='printer.brl.nyc,biggie.brl.nyc,smalls.brl.nyc,tiny.brl.nyc,reception.brl.nyc,intern02.brl.nyc,intheoffice.brl.nyc,audiobot.brl.nyc,bustedpi.brl.nyc,pfSense.brl.nyc,intern06.brl.nyc,intern04.brl.nyc,north.brl.nyc,south.brl.nyc,longrange.brl.nyc,lite.brl.nyc,NPI6BBE68.brl.nyc'
ENV['SLACK_HOOK_URL']='https://hooks.slack.com/services/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'
module BenevolentGaze
  class Kiosk < Sinatra::Base
    set server: 'thin', connections: []
    set :bind, '0.0.0.0'
    set :app_file, __FILE__
    set :port, ENV['IPORT']
    set :static, true
    set :public_folder, ENV['PUBLIC_FOLDER'] || "public"
    @@local_file_system = ENV['PUBLIC_FOLDER']

    register Sinatra::CrossOrigin

    configure do
      unless ENV['AWS_ACCESS_KEY_ID'].nil? || ENV['AWS_ACCESS_KEY_ID'].empty? || ENV['AWS_SECRET_ACCESS_KEY'].empty? || ENV['AWS_CDN_BUCKET'].empty?
        USE_AWS = true
      else
        USE_AWS = false
      end

      if ENV['IGNORE_HOSTS'].nil?
        IGNORE_HOSTS = false
      else
        IGNORE_HOSTS = ENV['IGNORE_HOSTS'].split(',')
      end

      Slack.configure do |config|
        config.token = ENV['SLACK_API_TOKEN'] || 'xoxb-20159046901-w2V7crilpVg7Uxcr5fpFMdxl'
      end
      @slack = Slack::Web::Client.new

    end

    before do
      @r = Redis.new
    end

    helpers do
      def get_ip
        if request.ip == '127.0.0.1'
           env['HTTP_X_REAL_IP'] || env['HTTP_X_FORWARDED_FOR']
        else
          request.ip
        end
      end

      def lookup_slack_id(slack_name)
        res = @r.hget('slack_id:slack_name',slack_name)
        return res if res
        slack_name.prepend("@") if slack_name[0] != "@"
        begin
          res = @slack.users_info(user: slack_name)
          slack_id = res["user"]["id"]
          @r.hset('slack_id:slack_name', slack_id, slack_name)
          @r.hset('slack_id:slack_name', slack_name, slack_id)
          return
        rescue Exception
          # throws an exception if user not found.
          return false
        end
      end

      def slack_id_to_name(slack_id)
        res = @r.hget('slack_id:slack_name',slack_id)
        return res if res
        begin
          res = @slack.users_info(user: slack_id)
          slack_name = res["user"]["name"].prepend("@")
          @r.hset('slack_id:slack_name', slack_id, slack_name)
          @r.hset('slack_id:slack_name', slack_name, slack_id)
          return slack_name
        rescue Exception
          # throws an exception if user not found.
          return false
        end
      end

      def is_slack_user_online(slack_name)
        slack_name.prepend("@") if slack_name[0] != "@"
        begin
          res = @slack.users_getPresence(user: slack_name)
          return res["presence"] == "active"
        rescue Exception
          # throws an exception if user not found.
          return false
        end
      end

      def upload(filename, file, device_name)
          doomsday = Time.mktime(2038, 1, 18).to_i
          if (filename)
            new_file_name = device_name.to_s + SecureRandom.uuid.to_s + filename
            bucket = ENV['AWS_CDN_BUCKET']
            image = MiniMagick::Image.open(file.path)

            animated_gif = `identify -format "%n" "#{file.path}"`.to_i > 1
            if animated_gif
              image.repage "0x0"
              if image.height > image.width
                image.resize "300"
                offset = (image.height/2) - 150
                image.crop("300x300+0+#{offset}")
              else
                image.resize "x300"
                offset = (image.width/2) - 150
                image.crop("300x300+#{offset}+0")
              end
              image << "+repage"
            else
              image.auto_orient
              if image.height > image.width
                image.resize "300"
                offset = (image.height/2) - 150
                image.crop("300x300+0+#{offset}")
              else
                image.resize "x300"
                offset = (image.width/2) - 150
                image.crop("300x300+#{offset}+0")
              end
              image.format "png"
            end

            if USE_AWS
              AWS::S3::Base.establish_connection!(
                :access_key_id     => ENV['AWS_ACCESS_KEY_ID'],
                :secret_access_key => ENV['AWS_SECRET_ACCESS_KEY']
              )
              AWS::S3::S3Object.store(
                new_file_name,
                image.to_blob,
                bucket,
                :access => :public_read
              )
              image_url = AWS::S3::S3Object.url_for( new_file_name, bucket, :expires => doomsday )
            else
              upload_path =  @@local_file_system + '/images/uploads/'
              file_on_disk = upload_path + new_file_name
              File.open(File.expand_path(file_on_disk), "w") do |f|
                f.write(image.to_blob)
              end
              image_url = "images/uploads/" + new_file_name
            end

            return image_url

          else
            return nil
          end
      end
    end

    get "/" do
      send_file "public/index.html"
    end

    get "/is_registered" do
      begin
        dns = Resolv.new
        device_name = dns.getname(get_ip())

        result = @r.exists("name:#{device_name}").to_s
      rescue Exception
        result = false
      end
      return result
    end

    get "/ip" do
      get_ip()
    end

    get "/me" do
      # return my data: image, name, slack name device name, etc.
    end

    get "/env" do
      ENV.each_pair{|k,v|
        puts "#{k}:#{v} \n"
      }
    end

    get "/dns" do
      dns = Resolv.new
      begin
       return dns.getname(get_ip())
      rescue Exception
        return false
      end
    end

    post "search" do
      if params[:slack]
        devices = @r.keys("slack:*").select{|k| @r.get(k)==params[:slack]}
        # if device exists, return true, else false
        return !devices.detect {|d| @r.hexists("current_devices",d) }.nil?
      elsif params[:name]
        names = @r.keys("name:*").select{|k| @r.get(k)==params[:name]}
        return !names.detect {|d| @r.hexists("current_devices",d) }.nil?
      end
    end

    post "/register" do
      dns = Resolv.new
      device_name = dns.getname(get_ip())


      compound_name = nil

      if !params[:real_first_name].empty? || !params[:real_last_name].empty?
        compound_name = "#{params[:real_first_name].to_s.strip} #{params[:real_last_name].to_s.strip}"
        @r.set("name:#{device_name}", compound_name)
      end

      # if params[:slack_name]
      #   slack_name = params[:slack_name].to_s.strip
      #   slack_id = lookup_slack_id(slack_name)

      #   if slack_id
      #     @r.set("slack:#{device_name}", slack_name)
      #     @r.set("slack_id:#{device_name}", slack_id)
      #   else
      #     status 401
      #     return {success:false,msg:"slack name not found"}.to_json
      #   end
      # end

      if params[:fileToUpload]
        image_url_returned_from_upload_function = upload(params[:fileToUpload][:filename], params[:fileToUpload][:tempfile], device_name)
        name_key = "image:" + (compound_name || @r.get("name:#{device_name}") || device_name)
        @r.set(name_key, image_url_returned_from_upload_function)
      end
      status 200
      redirect "/"
    end

    get "/register" do
      send_file "public/register.html"
    end

    get "/msgs", provides: 'text/event-stream' do
      cross_origin

      stream :keep_open do |out|
        loop do
          if out.closed?
            break
          end
          r = Redis.new
          r.subscribe('slackback') do |on|
            on.message do |channel,message|
              m = JSON.parse(message)
              slack_name = slack_id_to_name(m['user'])
              data = {msg: m['msg'], user: slack_name}.to_json
              out << "data: #{data}\n\n"
            end
          end
        end
      end
    end

    get "/feed", provides: 'text/event-stream' do
      cross_origin

      stream :keep_open do |out|
        loop do
          if out.closed?
            break
          end
          data = []
          @r = Redis.new
          @r.hgetall("current_devices").each do |k,v|
            name_or_device_name = @r.get("name:#{k}") || k
            slack = @r.get("slack:#{k}") || false
            data << { device_name: k, name: v, slack_name: slack, last_seen: (Time.now.to_f * 1000).to_i, avatar: @r.get("image:#{name_or_device_name}") }
          end

          out << "data: #{data.to_json}\n\n"
          sleep 1
        end
      end
    end

    post '/ping/' do

      to = params[:to]
      to.prepend("@") if to[0] != "@"

      # throttle our messages. 1 minute
      if @r.get("msg_throttle:#{to}")
        status 420 #enhance your chill
        return {success:false, msg: "enhance your chill."}.to_json
      else
        @r.setex("msg_throttle:#{to}",60, true)
      end

      begin
        dns = Resolv.new
        device_name = dns.getname(get_ip())

        result = @r.get("slack:#{device_name}")
        if result.nil?
          result = @r.get("name:#{device_name}")
        end
      rescue Exception
        status 404
        return {success:false, msg: "We can't seem to figure out who you are."}.to_json
      end
      from = result.to_s

      from.prepend('@') if from[0] !="@"

      to_id = lookup_slack_id(to)
      from_id = lookup_slack_id(from)
      if from_id
        from_id = from_id.prepend("<@") + ">"
      else
        from_id = from
      end
      # no user found!
      unless to_id
        status 404
        return {success:false,msg: "the person you're trying to ping isn't on slack"}.to_json
      end

      # should be using this: https://api.slack.com/methods/chat.postMessage
      # post as bot to IM channel
      res = @slack.chat_postMessage(channel: to, text: "ping from #{from}, responses to me will be posted on the board.", as_user: true)

      if res['ok'] == true
        status 200
        return {success:true}.to_json
      else
        status 400
        return {success:false,msg: "something went horribly wrong."}.to_json
      end
    end

    post "/information" do
      #grab current devices on network.  Save them to the devices on network key after we make sure that we grab the names that have been added already to the whole list and then save them to the updated hash for redis.
      devices_on_network = JSON.parse(params[:devices])
      if IGNORE_HOSTS != false
        devices_on_network.delete_if{|k,v| IGNORE_HOSTS.include?(k)}
      end
      old_set = @r.hkeys("current_devices")
      new_set = devices_on_network.keys
      diff_set = old_set - new_set

      diff_set.each do |d|
        @r.hdel("current_devices", d)
      end

      devices_on_network.each do |k,v|
        @r.hmset("current_devices", k, @r.get("name:#{k}"))
      end
    end
  end
end
