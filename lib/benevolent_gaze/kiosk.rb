require 'json'
require 'sinatra/base'
require 'sinatra/advanced_routes'
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
require 'net/ping'
require 'picky'
require 'slack-ruby-client'
require 'google/apis/calendar_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'active_support/core_ext/time'
require 'securerandom'
require 'set'

Encoding.default_external = 'utf-8' if defined?(::Encoding)
# slack names do not have an @ in front of them for our purposes.
# for slack, they do.

module BenevolentGaze
  class Kiosk < Sinatra::Application
    set server: 'thin', connections: Set.new
    set :bind, ENV['BIND_IP'] || '0.0.0.0'
    set :app_file, __FILE__
    set :port, ENV['IPORT']
    set :admin_email, ENV['ADMIN_EMAIL'] || "admin@#{ENV['SERVER_HOST']}"
    set :static, true
    set :logging, true
    set :public_folder, ENV['PUBLIC_FOLDER'] || 'public'
    @@local_file_system = ENV['PUBLIC_FOLDER'] || 'public'

    register Sinatra::CrossOrigin

    configure do
      if ENV['AWS_ACCESS_KEY_ID'].nil? || ENV['AWS_ACCESS_KEY_ID'].empty? || ENV['AWS_SECRET_ACCESS_KEY'].empty? || ENV['AWS_CDN_BUCKET'].empty?
        USE_AWS = false
      else
        USE_AWS = true
      end

      IGNORE_HOSTS = if ENV['IGNORE_HOSTS'].nil?
                       false
                     else
                       ENV['IGNORE_HOSTS'].split(',')
                     end

      Slack.configure do |config|
        config.token = ENV['SLACK_API_TOKEN']
      end

      OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'.freeze
      APPLICATION_NAME = 'Blue Ridge Calendaring'.freeze

      if File.exist?('/etc/bg/client_secret.json')
        CLIENT_SECRETS_PATH = '/etc/bg/client_secret.json'.freeze
        CREDENTIALS_PATH = File.join('/etc/bg/.credentials/calendar-ruby-quickstart.yaml')
      else
        CLIENT_SECRETS_PATH = '../client_secret.json'.freeze
        CREDENTIALS_PATH = File.join(Dir.home, '.credentials',
                                     'calendar-ruby-quickstart.yaml')
      end

      SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR

      # to refactor into config system
      CALENDAR_IDS = {
        'biggie' => 'robinhood.org_2d33313439373439322d363134@resource.calendar.google.com',
        'smalls' => 'robinhood.org_3730373137363538363534@resource.calendar.google.com',
        'tiny' => 'robinhood.org_2d37313337333130363239@resource.calendar.google.com'
      }.freeze
    end

    before do
      @r = Redis.new
      @slack = Slack::Web::Client.new
      @dns = Resolv.new
      logger.datetime_format = '%Y/%m/%d @ %H:%M:%S '
      logger.level = Logger::INFO
    end

    helpers do
      def get_user_info
        # returns a hash with all the user info we have given an IP address
        begin
          device_name = @dns.getname(find_ip)
          return false unless @r.exists("name:#{device_name}")
        rescue Resolv::ResolvError
          return false
        end
        name = @r.hget('current_devices', device_name)
        name = @r.get("name:#{device_name}") if name.nil?
        name_or_device_name = name ? name : device_name
        slack_name = @r.get("slack:#{device_name}")
        slack_id = @r.hget('slack_id2slack_name', slack_name)
        { real_name: name,
          slack_name: slack_name,
          slack_id: slack_id,
          device_name: device_name,
          avatar: @r.get("image:#{name_or_device_name}") }
      end

      def door_auth?
        !ENV['KISI_DOOR_URL'].nil? && get_user_info != false
      end

      def find_ip
        if request.ip == '127.0.0.1'
          env['HTTP_X_REAL_IP'] || env['HTTP_X_FORWARDED_FOR']
        else
          request.ip
        end
      end

      def ping(host)
        p = Net::Ping::External.new(host)
        # or makes sense here, actually. first pings can sometimes fail as
        # the device might be asleep...
        p.ping? or p.ping? or p.ping? # rubocop:disable Style/AndOr
      end

      def find_devicename(ip = nil)
        @dns.getname(ip || find_ip)
      rescue Resolv::ResolvError
        return false
      end

      def lookup_slack_id(slack_name)
        s = slack_name.dup.delete('@')
        res = @r.hget('slack_id2slack_name', s)
        return res if res
        begin
          res = get_slack_info(slack_name)
          @r.hset('slack_id2slack_name', res['user']['id'], s)
          @r.hset('slack_id2slack_name', s, res['user']['id'])
          return res['user']['id']
        rescue Slack::Web::Api::Error
          # throws an exception if user not found.
          return false
        end
      end

      def get_slack_info(sname)
        s = sname.dup.prepend('@') if sname[0] != 'U'
        @slack.users_info(user: s)
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
        rescue Slack::Web::Api::Error
          # throws an exception if user not found.
          return false
        end
      end

      def is_slack_user_online(sname)
        s = sname.dup.prepend('@') if sname[0] != '@'
        begin
          if @slack.users_getPresence(user: s)['presence'] == 'active'
            @r.sadd 'current_slackers', lookup_slack_id(s)
            return true
          else
            @r.srem 'current_slackers', lookup_slack_id(s)
            return false
          end
        rescue Slack::Web::Api::Error
          # throws an exception if user not found.
          return false
        end
      end

      # this is to access the google calendar. see /calendar below
      def service
        return @service unless @service.nil?

        client_id = Google::Auth::ClientId.from_file(CLIENT_SECRETS_PATH)
        token_store = Google::Auth::Stores::FileTokenStore.new(file: CREDENTIALS_PATH)
        authorizer = Google::Auth::UserAuthorizer.new(
          client_id, SCOPE, token_store
        )
        user_id = 'bill@robinhood.org'
        credentials = authorizer.get_credentials(user_id)
        @service = Google::Apis::CalendarV3::CalendarService.new
        @service.client_options.application_name = APPLICATION_NAME
        @service.authorization = credentials
        @service
      end

      def calendar_name_to_id(name)
        CALENDAR_IDS[name]
      end

      def gen_cal_id
        SecureRandom.uuid.to_s.delete('-')
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

    # static file requests
    get '/' do
      send_file 'public/index.html'
    end

    get '/register' do
      send_file 'public/register.html'
    end

    get '/calendar' do
      send_file 'public/calendar.html'
    end

    # checks for the front end if we can door.
    get '/can_door' do
      door_auth?
    end

    # How you door
    get '/downstairs_door' do
      if !door_auth?
        status 404
        return ''
      elsif @r.exists("door_throttle:#{find_ip}")
        status 420 # enhance your chill
        return { success: false, msg: 'enhance your chill.' }.to_json
      else
        @r.setex("door_throttle:#{find_ip}", 15, true)
        url = ENV['KISI_DOOR_URL']
        res = HTTParty.get(url)
        if res.code == 200
          return { success: true, data: res }.to_json
        else
          status 400
          return { success: false, data: res.code }.to_json
        end
      end
    end

    get '/is_registered' do
      # do we want to keep this only for registered users?
      begin
        dns = Resolv.new
        device_name = dns.getname(find_ip)
        return @r.exists("name:#{device_name}")
      rescue Resolv::ResolvError
        return false
      end
    end

    get '/ip' do
      find_ip
    end

    get '/ping' do
      if ping(find_ip)
        status 200
        return { success: true }.to_json
      else
        status 404
        return { success: false }.to_json
      end
    end

    get '/me' do
      data = get_user_info
      if data
        status 200
        return { success: true, data: data }.to_json
      else
        status 400
        return { success: false }.to_json
      end
    end

    # usefull for debugging...
    # get '/env' do
    #   res = []
    #   ENV.each_pair do |k, v|
    #     res << { k => v }
    #   end
    #   res.to_json
    # end

    get '/dns' do
      begin
        return @dns.getname(find_ip)
      rescue Resolv::ResolvError
        status 404
        return false
      end
    end

    get '/slack_names.json' do
      # search for slack ids based on user input. do a typeahead thing.
      @slack.users_list.members.map(&:name).to_json
    end

    post '/send_slack_invite' do
      # send invitation to slack user
      slack_id = lookup_slack_id(params[:slack_name])
      if slack_id
        @slack.chat_postMessage(channel: slack_id,
                                text: "Hi! Welcome! To get setup, click on this link http://#{ENV['SERVER_HOST']}/slack_me_up/#{slack_id} when you are in the office, connected to the wifi. (It won't work anywhere else.)",
                                as_user: true)
        status 200
        return true
      else
        status 404
        return false
      end
    end

    get '/slack_me_up/:id' do
      unless ping(find_ip)
        status 404
        return { success: false, msg: 'we cannot ping your device' }.to_json
      end

      device_name = find_devicename
      slack_info = get_slack_info(params['id'])

      if device_name && slack_info
        u_data = slack_info['user']

        # hunting for a name...
        name = u_data['profile']['real_name_normalized']
        name = u_data['real_name'] if name.empty?
        name = u_data['profile']['real_name'] if name.empty?
        name = u_data['name'] if name.empty?
        name = name.empty? ? device_name : name

        @r.set("name:#{device_name}", name)
        @r.set("slack:#{device_name}", u_data['name'])
        @r.set("slack_id:#{device_name}", slack_id)
        @r.sadd('all_devices', device_name)
        @r.set("email:#{device_name}", u_data['email'])
        image_url = u_data['profile']['image_512']
        image_name_key = "image:#{name}"
        @r.set(image_name_key, image_url)

        status 200
        redirect '/'
      else
        status 402
        msg = "slack:#{slack_info ? 'true' : 'false'} device:#{device_name ? 'true' : 'false'}"
        return { success: false, msg: msg }.to_json
      end
    end

    # currently unused. all searching is now frontend.
    # post 'search' do
    #   if params[:slack]
    #     devices = @r.keys('slack:*').select { |k| @r.get(k) == params[:slack] }
    #     # if device exists, return true, else false
    #     return !devices.detect { |d| @r.hexists('current_devices', d) }.nil?
    #   elsif params[:name]
    #     names = @r.keys('name:*').select { |k| @r.get(k) == params[:name] }
    #     return !names.detect { |d| @r.hexists('current_devices', d) }.nil?
    #   end
    # end

    post '/register' do
      # no registration for un-pingable devices
      unless ping(find_ip)
        status 404
        return { success: false, msg: 'we cannot ping your device' }.to_json
      end

      device_name = find_devicename
      unless device_name
        status 500
        return { success: false, msg: 'we cannot seem to find your IP address' }.to_json
      end

      real_name = nil

      if params[:real_name].empty?
        status 401
        return "Please tell us your name! <a href='/register'>go back and try again.</a>"
      else
        real_name = params[:real_name].to_s.strip
      end

      image_name_key = "image:#{real_name}"

      if params[:slack_name]
        slack_name = params[:slack_name].to_s.strip
        slack_name.delete!('@')
        slack_id = lookup_slack_id(slack_name)

        if slack_id
          # no @ in data-slackname! breaks jquery
          @r.set("slack:#{device_name}", slack_name)
          @r.set("slack_id:#{device_name}", slack_id)
          res = get_slack_info(slack_id)
          @r.set(image_name_key, res['user']['profile']['image_512'])
          @r.set("email:#{device_name}", res['user']['profile']['email'] || '')
        else
          # this shouldn't happen, we finlter on the front end.
          status 401
          return "slack name not found, <a href='/register'>go back and try again.</a>"
        end
      end

      if params[:fileToUpload]
        image_url_returned_from_upload_function = upload(params[:fileToUpload][:filename], params[:fileToUpload][:tempfile], device_name)
        @r.set(image_name_key, image_url_returned_from_upload_function)
      end

      @r.set("name:#{device_name}", real_name)
      @r.sadd('all_devices', device_name) # set of all devices
      status 200
      redirect '/'
    end

    get '/event' do
      begin
        calendar_id = calendar_name_to_id(params[:calendar])
        event = service.get_event(calendar_id, params[:id])
        status 200
        return { success: true, event: event }.to_json
      rescue Google::Apis::ClientError => e
        status 410
        return { success: false, msg: e }.to_json
      end
    end

    delete '/calendar' do
      calendar_id = calendar_name_to_id(params[:calendar])
      begin
        service.delete_event(calendar_id, params[:id])
        status 200
        return { success: true }.to_json
      rescue Google::Apis::ClientError => e
        status 410
        return { success: false, msg: e }.to_json
      end
    end

    # event is in the calendar we think it is, update.
    # event is in another calendar,find it, move it, and then update
    # event isn't in any calendar, it's new! create it!
    #
    # handle the creation & editing of events.
    post '/calendar' do
      user = get_user_info
      if user == false
        status 410
        return { success: false }.to_json
      end

      Time.zone = ENV['TIME_ZONE'] || 'America/New_York'
      e_id      = params[:id]
      e_start   = Time.parse(params[:start]).to_datetime.rfc3339
      e_end     = Time.parse(params[:end]).to_datetime.rfc3339
      calendar  = params[:calendar]
      title     = params[:title]

      calendar_id = calendar_name_to_id(calendar)
      event = nil
      old_cal_id = nil
      begin
        # event found in this calendar.
        event = service.get_event(calendar_id, e_id)
        if event.status == 'cancelled'
          logger.info('event is cancelled')
          event = nil
          # e_id = gen_cal_id # we need a whole new event here.
        end
      rescue Google::Apis::ClientError => e
        logger.info("#{title} not in #{calendar} or new")
        logger.info(e)
        # event doesn't exist in this calendar.
        # find in others?
      end

      other_calendars = CALENDAR_IDS.values
      other_calendars.delete(calendar_id)

      if event.nil?
        other_calendars.each do |cal_id|
          begin
            event = service.get_event(cal_id, e_id)
            if event && event.status != 'cancelled'
              logger.info('event is in another calendar and not cancelled')
              old_cal_id = cal_id
            else
              logger.info('event is either cancelled or not in the calendar')
              event = nil
            end
          rescue Google::Apis::ClientError => e
            logger.info(e)
          end
        end
      end

      if !event.nil?
        logger.info('event exists and not cancelled')
        if old_cal_id
          # we move the event if it was in another calendar
          logger.info('moving event!')
          event = service.move_event(old_cal_id, event.id, calendar_id)
          logger.info(event.status)
        end
        event.sequence += 2
        event.start.date_time = e_start
        event.end.date_time = e_end
        event.status = 'confirmed'
        event.location = calendar
        event.creator.displayName = user[:name]
        event.creator.email = user[:email] unless user[:email].nil?
        res = service.update_event(calendar_id, event.id, event)
        logger.info(res)
      else # wholly new event!
        logger.info('new event!')

        options = {
          id: e_id,
          summary: title,
          location: calendar,
          sequence: 1, # unclear if we need this
          description: title,
          creator: {
            displayName: user[:name] || 'unknown',
            email: user[:email] || 'blueridgelabs@robinhood.org'
          },
          start: { date_time: e_start },
          end: { date_time: e_end }
        }
        event = Google::Apis::CalendarV3::Event.new(options)
        service.insert_event(calendar_id, event)
      end

      status 200
      return { success: true }.to_json
    end

    get '/feed', provides: 'text/event-stream' do
      cross_origin
      response.headers['X-Accel-Buffering'] = 'no'
      stream :keep_open do |out|
        loop do
          break if out.closed?
          settings.connections << out # so we can use this stream elsewhere
          data = []
          @r = Redis.connect

          @r.hgetall('current_devices').each do |k, v|
            name_or_device_name = @r.get("name:#{k}") || k
            email = @r.get("email:#{k}")
            slack = @r.get("slack:#{k}") || false
            slack_id = @r.get("slack_id:#{k}")
            next unless slack # if you're not setup, we don't want to see you.

            online = false
            # if we have a slack, remove the @. if not, set to false
            if slack
              slack.delete!('@')
              slack_id = lookup_slack_id(slack)
              online = @r.sismember('current_slackers', slack_id) || false
              if image_url.nil? || email.nil?
                # update missing info from slack
                res = get_slack_info(slack_id)
                @r.set("image:#{name_or_device_name}", res['user']['profile']['image_512'])
                @r.set("email:#{k}", res['user']['profile']['email'])
              end
            end
            image_url = @r.get("image:#{name_or_device_name}")

            data << { type: 'device',
                      device_name: k,
                      name: v,
                      online: online,
                      slack_name: slack,
                      last_seen: (Time.now.to_f * 1000).to_i,
                      avatar: image_url }
          end

          out << "data: #{data.to_json}\n\n"
          sleep 1
        end
      end
    end

    post '/slack_ping/' do
      to = params[:to]
      # throttle our messages. 30 second, "to" and IP
      if @r.get("msg_throttle:#{to}:#{find_ip}")
        status 420 # enhance your chill
        return { success: false, msg: 'enhance your chill.' }.to_json
      end

      begin

        device_name = @dns.getname(find_ip)
        if device_name != ENV['KIOSK_HOST']
          result = @r.get("slack:#{device_name}")
          result = @r.get("name:#{device_name}") if result.nil?
          from = result.to_s

          from_id = lookup_slack_id(from)
          from = from_id ? from_id.prepend('<@') + '>' : 'Someone at 150 Court'
        else
          from = 'The Front Desk'
        end
      rescue Resolv::ResolvError => e
        status 400
        return { success: false,
                 msg: "We can't seem to figure out who you are. #{e}" }.to_json
      end

      to_id = lookup_slack_id(to)
      # no user found!
      unless to_id
        status 412
        return { success: false,
                 msg: "the person you're trying to ping isn't on slack" }.to_json
      end

      unless is_slack_user_online(to)
        status 412
        return { success: false, msg: "@#{to} isn't currently online. Try someone else?" }.to_json
      end

      res = @slack.chat_postMessage(channel: "@#{to}",
                                    text: "ping from #{from}, responses to me will be posted on the board.",
                                    as_user: true)
      # set throttle
      @r.setex("msg_throttle:#{to}:#{find_ip}", 30, true)

      if res['ok'] == true
        status 200
        return { success: true }.to_json
      else
        status 400
        return { success: false, msg: 'something went horribly wrong.' }.to_json
      end
    end

    post '/msg' do
      return false unless params[:msg_token] == ENV['MSG_TOKEN']
      m = JSON.parse(params[:msg])
      slack_name = slack_id_to_name(m['user'])
      if slack_name != false
        # we used to send arrays.
        msg = [{ id: SecureRandom.uuid.to_s, type: 'msg', msg: m['msg'], user: slack_name.delete('@') }]
        # https://github.com/sinatra/sinatra/blob/master/examples/chat.rb
        settings.connections.each { |out| out << "data: #{msg.to_json}\n\n" }
        status 204 # response without entity body
      else
        status 404
      end
    end

    post '/information' do
      # grab current devices on network.
      # Save them to the devices on network key after we make sure that we
      # grab the names that have been added already to the whole list and
      # then save them to the updated hash (set?)for redis.

      # or push them out to all the clients.
      # https://blog.alexmaccaw.com/killing-a-library

      devices_on_network = JSON.parse(params[:devices])
      if IGNORE_HOSTS != false
        devices_on_network.delete_if { |k, _v| IGNORE_HOSTS.include?(k) }
      end

      # deletes devices not in new batch
      old_set = @r.hkeys('current_devices')
      new_set = devices_on_network.keys
      diff_set = old_set - new_set
      diff_set.each do |d|
        @r.hdel('current_devices', d)
      end

      # adds devices in new batch in.
      # there will be some overwrites. OK: updates with new data
      devices_on_network.each do |k, _v|
        @r.hmset('current_devices', k, @r.get("name:#{k}"))
      end
      status 204 # response without entity body
    end
  end
end
