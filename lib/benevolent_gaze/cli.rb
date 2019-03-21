require 'thor'
require 'thor/actions'
require 'csv'
require 'benevolent_gaze/kiosk'
require 'benevolent_gaze/tracker'
require 'benevolent_gaze/slacker'

include FileUtils

module BenevolentGaze
  class Cli < Thor
    include Thor::Actions
    source_root File.expand_path('../../kiosk', __dir__)

    desc 'kiosk', 'Start up the sinatra app that displays the users'
    def kiosk
      BenevolentGaze::Kiosk.run!
    end

    desc 'tracker', 'Start up the tracking daemon that looks at the network'
    def tracker
      BenevolentGaze::Tracker.run!
    end

    desc 'slacker', 'Start up the slackbot'
    def slacker
      BenevolentGaze::Slacker.run
    end

    desc 'add_user device name image', "Add single user's device name, name, slack username and image"
    long_desc <<-LONGDESC
      This command takes a user's device name, real name, image url, and slack username and maps them
      so that Benevolent Gaze can use the information when they log onto your network.
    LONGDESC

    def add_user(device_name, name, image_url, slack = nil)
      redis = Redis.new

      redis.set "name:#{device_name}", name
      redis.set "image:#{name}", image_url
      redis.set "slack:#{device_name}", slack if slack
      redis.sadd 'all_devices', device_name
    end

    desc 'assign_users', 'This will prompt you for each current user without an associated name so that you can assign one.'
    def assign_users
      require 'redis'
      redis = Redis.new
      devices = redis.smembers('current_devices')
      users = {}
      devices.each { |d| users[d] = redis.get("name:#{d}") }

      puts 'Right now, these are the devices on your network'
      users.each { |u, _v| puts "  #{u}" }

      users.each do |u, val|
        val = redis.get "name:#{u}"
        if val.nil? || val.empty?
          puts "Do you know whose device this is #{u}? ( y/n )"
          response = $stdin.gets.chomp.strip
          if response == 'y'
            puts 'Please enter their name.'
            name_response = $stdin.gets.chomp.strip
            redis.set "name:#{u}", name_response.to_s
            # `redis-cli set "name:#{u}" "#{name_response}"`

            puts 'Do you have an image for this user? ( y/n )'
            image_response = $stdin.gets.chomp.strip
            if image_response == 'y'
              puts 'Please enter the image url.'
              image_url_response = $stdin.gets.chomp.strip
              redis.set "image:#{name_response}", image_url_response
            end

            puts 'Please enter their slack username, with @ prepended.'
            slack_response = $stdin.gets.chomp.strip
            redis.set "slack:#{u}", slack_response.to_s

          end
        else
          puts "#{Thor::Shell::Color::MAGENTA}#{u} looks like it has a name already associated with them.#{Thor::Shell::Color::CLEAR}"
        end
      end
      bg_flair
    end

    desc 'dump_csv [FILENAME]', 'This dumps all registered_devices'
    def dump_csv(filename)
      require 'redis'
      redis = Redis.new
      devices = redis.smembers 'all_devices'
      CSV.open(filename, 'wb') do |out|
        devices.each do |device|
          name = redis.get "name:#{device}"
          image = redis.get "image:#{name}"
          slack = redis.get "slack:#{device}"
          slack_id = redis.get "slack_id:#{device}"
          out << [device, name, image, slack, slack_id]
        end
      end
      bg_flair
      puts "#{filename} created"
    end

    desc 'bulk_assign yourcsv.csv', 'This takes a csv file as an argument formated in the following way. device_name, real_name, image_url'
    def bulk_assign(csv_path)
      redis = Redis.new
      CSV.foreach(csv_path) do |row|
        puts "Loading device info for #{row[0]} -> #{row[1]}"
        device_name = row[0]
        real_name = row[1]
        image_url = row[2]
        slack_name = row[3]
        slack_id = row[4]

        redis.sadd('all_devices', device_name)

        unless real_name.nil? || real_name.empty?
          redis.set "name:#{device_name}", real_name
        end

        unless slack_name.nil? || slack_name.empty?
          redis.set "slack:#{device_name}", slack_name
          redis.set "slack_id:#{device_name}", slack_id
          redis.hset 'slack_id2slack_name', slack_id, slack_name
          redis.hset 'slack_id2slack_name', slack_name, slack_id
        end

        unless image_url.nil? || image_url.empty?
          redis.set "image:#{real_name}", image_url
        end
      end
      # puts `redis-cli keys "*"`
      puts "#{Thor::Shell::Color::MAGENTA}The CSV has now been added.#{Thor::Shell::Color::CLEAR}"
      bg_flair
    end

    desc 'install', 'This commands installs the necessary components in the gem and pulls the assets into a local folder so that you can save to your local file system if you do not want to use s3 and also enables you to customize your kiosk.'
    def install
      directory '.', 'bg_public'
      env_file = 'bg_public/.env'
      new_path = File.expand_path('./bg_public')
      gsub_file(env_file, /.*PUBLIC_FOLDER.*/, "PUBLIC_FOLDER=\"#{new_path}/public\"")

      puts <<-CUSTOMIZE

      #{Thor::Shell::Color::MAGENTA}**************************************************#{Thor::Shell::Color::CLEAR}

      Generated the bg_public folder where you should go to customize images and to run

      ```foreman start```

      Please modify the .env file with the relevant information mentioned in the README.

      You can now customize your kiosk, by switching out the graphics in the images folder.
      Please replace the images with the images of the same size.

      Uploaded images will save to your local filesystem if you do not supply AWS creds.

      #{Thor::Shell::Color::MAGENTA}**************************************************#{Thor::Shell::Color::CLEAR}
      CUSTOMIZE

      bg_flair
    end

    desc 'bg_flair prints Benevolent Gaze in ascii art letters, because awesome.', "This command prints Benevolent Gaze in ascii art letters, because...um...well...it's cool looking!"
    def bg_flair
      @bg = <<-BG
        #{Thor::Shell::Color::CYAN}
    ____                             _            _      _____
   |  _ \\                           | |          | |    / ____|
   | |_) | ___ _ __   _____   _____ | | ___ _ __ | |_  | |  __  __ _ _______
   |  _ < / _ \\ '_ \\ / _ \\ \\ / / _ \\| |/ _ \\ '_ \\| __| | | |_ |/ _` |_  / _ \\
   | |_) |  __/ | | |  __/\\ V / (_) | |  __/ | | | |_  | |__| | (_| |/ /  __/
   |____/ \\___|_| |_|\\___| \\_/ \\___/|_|\\___|_| |_|\\__|  \\_____|\\__,_/___\\___|

        #{Thor::Shell::Color::CLEAR}
      BG
      puts @bg
    end
  end
end
