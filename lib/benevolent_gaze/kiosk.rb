require 'json'
require 'sinatra/base'
require 'sinatra/support'
require 'sinatra/json'
require 'redis'
require 'resolv'
require 'sinatra/cross_origin'
require 'aws/s3'
require 'SecureRandom'
require 'mini_magick'

Encoding.default_external = 'utf-8'  if defined?(::Encoding)

module BenevolentGaze
  class Kiosk < Sinatra::Base
    set server: 'thin', connections: []
    set :bind, '0.0.0.0'
    set :app_file, __FILE__
    set :port, ENV['PORT']
    set :static, true
    set :public_folder, File.expand_path( "../../../frontend/build", __FILE__ )
    
    register Sinatra::CrossOrigin

    helpers do
      def upload(filename, file, device_name)
        doomsday = Time.mktime(2038, 1, 18).to_i
        if (filename)
          new_file_name = device_name.to_s + SecureRandom.uuid.to_s + filename.gsub(".jpg", ".png")
          bucket = ENV['AWS_CDN_BUCKET']
          image = MiniMagick::Image.open(file.path)
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
          return image_url 
        else
          return nil
        end
      end
    end

    get "/" do
      redirect "index.html"
    end
    
    post "/register" do
      dns = Resolv.new
      device_name = dns.getname(request.ip)
      r = Redis.new
      r.set("name:"+device_name, (params[:real_first_name] + params[:real_last_name]))
      
      if params[:real_first_name] || params[:real_last_name]
        compound_name = "#{params[:real_first_name].to_s.strip}  #{params[:real_last_name].to_s.strip}"
        r.set("name:#{device_name}", compound_name)
      end
      if params[:fileToUpload]
        image_url_returned_from_upload_function = upload(params[:fileToUpload][:filename], params[:fileToUpload][:tempfile], device_name)
        r.set("image:#{device_name}", image_url_returned_from_upload)
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
            data << { device_name: k, name: v, last_seen: (Time.now.to_f * 1000).to_i, avatar: r.get("image:#{k}") } 
          end
  
          out << "data: #{data.to_json}\n\n"
          sleep 1
        end
      end
    end

    post "/information" do
      #grab current devices on network.  Save them to the devices on network key after we make sure that we grab the names that have been added already to the whole list and then save them to the updated hash for redis.
      devices_on_network = JSON.parse(params[:devices]) 
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
