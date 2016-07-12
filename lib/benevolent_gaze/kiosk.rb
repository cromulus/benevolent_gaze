require 'json'
require 'sinatra/base'
require 'sinatra/support'
require 'sinatra/json'
require 'redis'
require 'hiredis'
require 'em-synchrony'
require 'resolv'
require 'sinatra/cross_origin'
require 'aws/s3'
require 'securerandom'
require 'mini_magick'
require 'httparty'
require 'slack-ruby-client'

Encoding.default_external = 'utf-8' if defined?(::Encoding)
# slack names do not have an @ in front of them for our purposes.
# for slack, they do.

module BenevolentGaze
  class Kiosk < Sinatra::Base

    set server: 'thin', connections: []
    set :bind, '0.0.0.0'
    set :app_file, __FILE__
    set :port, ENV['IPORT']
    set :static, true
    set :public_folder, ENV['PUBLIC_FOLDER'] || 'public'
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
        config.token = ENV['SLACK_API_TOKEN']
      end
    end

    before do
      @r = Redis.new
      @slack = Slack::Web::Client.new
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
        slack_name.delete!('@')
        res = @r.hget('slack_id2slack_name', slack_name)
        return res if res

        begin
          res = get_slack_info(slack_name)
          slack_id = res['user']['id']
          @r.hset('slack_id2slack_name', slack_id, slack_name)
          @r.hset('slack_id2slack_name', slack_name, slack_id)
          return slack_id
        rescue Exception
          # throws an exception if user not found.
          return false
        end
      end

      def get_slack_info(sname)
        sname.prepend('@') if sname[0] != '@'
        res = @slack.users_info(user: sname)
        sname.delete!('@') #wtf.
        return res
      end

      def slack_id_to_name(slack_id)
        res = @r.hget('slack_id2slack_name', slack_id)
        return res.delete('@') if res
        begin
          res = @slack.users_info(user: slack_id)
          slack_name = res['user']['name'].delete('@')
          @r.hset('slack_id2slack_name', slack_id, slack_name)
          @r.hset('slack_id2slack_name', slack_name, slack_id)
          return slack_name
        rescue Exception
          # throws an exception if user not found.
          return false
        end
      end

      def is_slack_user_online(sname)
        sname.prepend('@') if sname[0] != '@'
        begin
          res = @slack.users_getPresence(user: sname)
          online = res['presence'] == 'active'
          @r.sadd 'current_slackers', lookup_slack_id(sname) if online
          sname.delete!('@')
          return online
        rescue Exception
          sname.delete!('@')
          # throws an exception if user not found.
          return false
        end
      end

      def upload(filename, file, device_name)
        doomsday = Time.mktime(2038, 1, 18).to_i
        if filename
          new_file_name = device_name.to_s + SecureRandom.uuid.to_s + filename
          bucket = ENV['AWS_CDN_BUCKET']
          image = MiniMagick::Image.open(file.path)

          animated_gif = `identify -format "%n" "#{file.path}"`.to_i > 1
          if animated_gif
            image.repage '0x0'
            if image.height > image.width
              image.resize '300'
              offset = (image.height / 2) - 150
              image.crop("300x300+0+#{offset}")
            else
              image.resize 'x300'
              offset = (image.width / 2) - 150
              image.crop("300x300+#{offset}+0")
            end
            image << '+repage'
          else
            image.auto_orient
            if image.height > image.width
              image.resize '300'
              offset = (image.height / 2) - 150
              image.crop("300x300+0+#{offset}")
            else
              image.resize 'x300'
              offset = (image.width / 2) - 150
              image.crop("300x300+#{offset}+0")
            end
            image.format 'png'
          end

          if USE_AWS
            AWS::S3::Base.establish_connection!(
              access_key_id: ENV['AWS_ACCESS_KEY_ID'],
              secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
            )
            AWS::S3::S3Object.store(
              new_file_name,
              image.to_blob,
              bucket,
              access: :public_read
            )
            image_url = AWS::S3::S3Object.url_for(new_file_name, bucket, expires: doomsday)
          else
            upload_path =  @@local_file_system + '/images/uploads/'
            file_on_disk = upload_path + new_file_name
            File.open(File.expand_path(file_on_disk), 'w') do |f|
              f.write(image.to_blob)
            end
            image_url = 'images/uploads/' + new_file_name
          end

          return image_url

        else
          return nil
        end
      end
    end

    get '/' do
      send_file 'public/index.html'
    end

    get '/is_registered' do
      begin
        dns = Resolv.new
        device_name = dns.getname(get_ip)

        result = @r.exists("name:#{device_name}").to_s
      rescue Exception
        result = false
      end
      return result
    end

    get '/ip' do
      get_ip
    end

    get '/me' do
      # return my data: image, name, slack name device name, etc.
    end

    get '/env' do
      ENV.each_pair do|k, v|
        puts "#{k}:#{v} \n"
        puts '<br>'
      end
    end

    get '/dns' do
      dns = Resolv.new
      begin
        return dns.getname(get_ip)
      rescue Exception
        status = 404
        return false
      end
    end

    post 'search' do
      if params[:slack]
        devices = @r.keys('slack:*').select { |k| @r.get(k) == params[:slack] }
        # if device exists, return true, else false
        return !devices.detect { |d| @r.hexists('current_devices', d) }.nil?
      elsif params[:name]
        names = @r.keys('name:*').select { |k| @r.get(k) == params[:name] }
        return !names.detect { |d| @r.hexists('current_devices', d) }.nil?
      end
    end

    post '/register' do
      dns = Resolv.new
      begin
        device_name = dns.getname(get_ip)
      rescue Exception => e
        status 500
        return { success: false, msg: 'we cannot seem to find your IP address' }.to_json
      end


      compound_name = nil

      if !params[:real_first_name].empty? || !params[:real_last_name].empty?
        compound_name = "#{params[:real_first_name].to_s.strip} #{params[:real_last_name].to_s.strip}"
        @r.set("name:#{device_name}", compound_name)
      end

      if params[:slack_name]
        slack_name = params[:slack_name].to_s.strip
        slack_name.delete!('@')
        slack_id = lookup_slack_id(slack_name)

        if slack_id
          # no @ in data-slackname! breaks jquery
          @r.set("slack:#{device_name}", slack_name)
          @r.set("slack_id:#{device_name}", slack_id)
        else
          status 401
          return { success: false, msg: 'slack name not found' }.to_json
        end
      end

      if params[:fileToUpload]
        image_url_returned_from_upload_function = upload(params[:fileToUpload][:filename], params[:fileToUpload][:tempfile], device_name)
        name_key = 'image:' + (compound_name || @r.get("name:#{device_name}") || device_name)
        @r.set(name_key, image_url_returned_from_upload_function)
      end
      status 200
      redirect '/'
    end

    get '/register' do
      send_file 'public/register.html'
    end

    # get '/msgs', provides: 'text/event-stream' do
    #   cross_origin
    #   response.headers['X-Accel-Buffering'] = 'no'
    #   stream :keep_open do |out|
    #     loop do
    #       break if out.closed?
    #       r = Redis.connect
    #       r.subscribe('slackback') do |on|
    #         on.message do |_channel, message|
    #           m = JSON.parse(message)
    #           slack_name = slack_id_to_name(m['user'])
    #           data = { msg: m['msg'], user: slack_name.delete('@') }.to_json
    #           out << "data: #{data}\n\n"
    #         end
    #       end
    #     end
    #   end
    # end

    get '/feed', provides: 'text/event-stream' do
      cross_origin
      response.headers['X-Accel-Buffering'] = 'no'
      stream :keep_open do |out|
        loop do
          break if out.closed?
          data = []
          @r = Redis.connect
          # grab all recent messages.
          while @r.llen('slackback') > 0
            m = JSON.parse(@r.lpop('slackback'))
            slack_name = slack_id_to_name(m['user'])
            data << { type: 'msg', msg: m['msg'], user: slack_name.delete('@') }
          end

          @r.hgetall('current_devices').each do |k, v|
            name_or_device_name = @r.get("name:#{k}") || k
            slack = @r.get("slack:#{k}") || false
            online = false
            # if we have a slack, remove the @. if not, set to false
            if slack
              slack.delete!('@')
              slack_id = lookup_slack_id(slack)
              online = @r.sismember('current_slackers', slack_id) || false
            end

            data << { type: 'device',
                      device_name: k,
                      name: v,
                      online: online,
                      slack_name: slack,
                      last_seen: (Time.now.to_f * 1000).to_i,
                      avatar: @r.get("image:#{name_or_device_name}") }
          end

          out << "data: #{data.to_json}\n\n"
          sleep 0.5
        end
      end
    end

    post '/ping/' do
      to = params[:to]
      to.prepend('@') if to[0] != '@'

      # throttle our messages. 1 minute
      if @r.get("msg_throttle:#{to}")
        status 420 # enhance your chill
        return { success: false, msg: 'enhance your chill.' }.to_json
      else
        @r.setex("msg_throttle:#{to}", 30, true)
      end

      begin
        dns = Resolv.new
        device_name = dns.getname(get_ip)

        result = @r.get("slack:#{device_name}")
        result = @r.get("name:#{device_name}") if result.nil?
      rescue Exception
        status 404
        return { success: false, msg: "We can't seem to figure out who you are." }.to_json
      end
      from = result.to_s

      to_id   = lookup_slack_id(to)
      from_id = lookup_slack_id(from)
      from = from_id ? from_id.prepend('<@') + '>' : from

      # no user found!
      unless to_id
        status 404
        return { success: false,
                 msg: "the person you're trying to ping isn't on slack" }.to_json
      end

      unless @r.sismember 'current_slackers', to_id
        status 404
        return { success: false, msg: "#{to} isn't currently online. Try someone else?" }.to_json
      end
      # should be using this: https://api.slack.com/methods/chat.postMessage
      # post as bot to IM channel
      res = @slack.chat_postMessage(channel: "@#{to}",
                                    text: "ping from #{from}, responses to me will be posted on the board.",
                                    as_user: true)

      if res['ok'] == true
        status 200
        return { success: true }.to_json
      else
        status 400
        return { success: false, msg: 'something went horribly wrong.' }.to_json
      end
    end

    post '/information' do
      # grab current devices on network.
      # Save them to the devices on network key after we make sure that we
      # grab the names that have been added already to the whole list and
      # then save them to the updated hash (set?)for redis.
      devices_on_network = JSON.parse(params[:devices])
      if IGNORE_HOSTS != false
        devices_on_network.delete_if { |k, _v| IGNORE_HOSTS.include?(k) }
      end
      old_set = @r.hkeys('current_devices')
      new_set = devices_on_network.keys
      diff_set = old_set - new_set

      diff_set.each do |d|
        @r.hdel('current_devices', d)
      end

      devices_on_network.each do |k, _v|
        @r.hmset('current_devices', k, @r.get("name:#{k}"))
      end
    end
  end
end
