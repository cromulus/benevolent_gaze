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

Encoding.default_external = 'utf-8'  if defined?(::Encoding)

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
    end

    helpers do
      def get_ip
        if request.ip == '127.0.0.1'
           env['HTTP_X_REAL_IP'] || env['HTTP_X_FORWARDED_FOR']
        else
          request.ip
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
      redirect "index.html"
    end

    get "/is_registered" do
      begin
        dns = Resolv.new
        device_name = dns.getname(get_ip())
        r = Redis.new
        result = r.exists("name:#{device_name}").to_s
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


    get "/dns" do
      dns = Resolv.new
      dns.getname(get_ip())
    end

    post "search" do
      if params[:slack]
        devices = r.keys("slack:*").select{|k| r.get(k)==params[:slack]}
        # if device exists, return true, else false
        return !devices.detect {|d| r.hexists("current_devices",d) }.nil?
      elsif params[:name]
        names = r.keys("name:*").select{|k| r.get(k)==params[:name]}
        return !names.detect {|d| r.hexists("current_devices",d) }.nil?
      end
    end

    post "/register" do
      dns = Resolv.new
      device_name = dns.getname(get_ip())
      r = Redis.new

      compound_name = nil

      if !params[:real_first_name].empty? || !params[:real_last_name].empty?
        compound_name = "#{params[:real_first_name].to_s.strip} #{params[:real_last_name].to_s.strip}"
        slack_name = params[:slack_name].to_s.strip
        r.set("name:#{device_name}", compound_name)
        r.set("slack:#{device_name}", slack_name)
      end
      if params[:fileToUpload]
        image_url_returned_from_upload_function = upload(params[:fileToUpload][:filename], params[:fileToUpload][:tempfile], device_name)
        name_key = "image:" + (compound_name || r.get("name:#{device_name}") || device_name)
        r.set(name_key, image_url_returned_from_upload_function)
      end
      redirect "thanks.html"
    end

    get "/register" do
      redirect "register.html"
    end

    get "/feed", provides: 'text/event-stream' do
      cross_origin
      r = Redis.new

      stream :keep_open do |out|
        loop do
          if out.closed?
            break
          end
          data = []
          r.hgetall("current_devices").each do |k,v|
            name_or_device_name = r.get("name:#{k}") || k
            slack = r.get("slack:#{k}") || false
            data << { device_name: k, name: v, slack_name: slack, last_seen: (Time.now.to_f * 1000).to_i, avatar: r.get("image:#{name_or_device_name}") }
          end

          out << "data: #{data.to_json}\n\n"
          sleep 1
        end
      end
    end

    post '/ping/' do
      to = params[:to]
      to.prepend("@") if to[0] != "@"
      begin
        dns = Resolv.new
        device_name = dns.getname(get_ip())
        r = Redis.new
        result = r.get("slack:#{device_name}")
        if result.nil?
          result = r.get("name:#{device_name}")
        end
      rescue Exception
        result = 'unknown'
      end
      from = result.to_s

      from.prepend('@') if from[0] !="@"

      msg = ''
      if from.include?('labs.robinhood.org') || to.include?('labs.robinhood.org')
        msg = "<http://intheoffice.labs.robinhood.org/register|Register> your computer & phone!"
      end

      res = HTTParty.post(ENV['SLACK_HOOK_URL'],
                    body: {username:"marco-polo-bot",
                            channel:"#{to}",
                            text:"Ping from #{from}",
                            "icon_emoji": ":ghost:" }.to_json )
      unless res.response.code = '200'
        HTTParty.post(ENV['SLACK_HOOK_URL'],
                    body: {username:"marco-polo-bot",
                            channel:"#general",
                            text:"#{from} pings #{to} #{msg}",
                            "icon_emoji": ":ghost:" }.to_json )
      end
    end

    post "/information" do
      #grab current devices on network.  Save them to the devices on network key after we make sure that we grab the names that have been added already to the whole list and then save them to the updated hash for redis.
      devices_on_network = JSON.parse(params[:devices])
      if IGNORE_HOSTS != false
        devices_on_network.delete_if{|k,v| IGNORE_HOSTS.include?(k)}
      end
      r = Redis.new
      old_set = r.hkeys("current_devices")
      new_set = devices_on_network.keys
      diff_set = old_set - new_set

      diff_set.each do |d|
        r.hdel("current_devices", d)
      end

      devices_on_network.each do |k,v|
        r.hmset("current_devices", k, r.get("name:#{k}"))
      end

    end
  end
end
