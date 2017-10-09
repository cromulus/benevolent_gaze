require 'resolv'
require 'redis'
require 'hiredis'
require 'parallel'
require 'timeout'
require 'dotenv'
Dotenv.load if ENV['SLACK_API_TOKEN'].nil?
# must run as root!

module BenevolentGaze
  class Tracker
    def self.run!
      @ignore_hosts = if ENV['IGNORE_HOSTS'].nil?
                        false
                      else
                        ENV['IGNORE_HOSTS'].split(',')
                      end
      @r = Redis.current # right? we've got redis right here.
      @dns = Resolv.new # not sure if we want to re-init resolve.
      @r.del('current_devices')

      # Run forever
      loop do
        do_scan
        sleep 1
      end
    end

    class << self
      private

      def ping(host)
        # must run as root!
        # or makes sense here, actually. first pings can sometimes fail as
        # the device might be asleep...
        res = false
        begin
          res = Timeout.timeout(1) do
            # pinging a host shouldn't take more than a few tenths of a second
            a = system("timeout 0.2 ping -c1 -q #{host}  > /dev/null 2>&1")
            b = system("timeout 0.2 ping -c1 -q #{host}  > /dev/null 2>&1")
            sleep(2)
            a || b
          end
        rescue Timeout::Error
          res = false
        end
        res
      end

      def do_scan
        # so, we don't want ALL hosts on LAN, just registered ones.
        # this could also be a request to to the web service too...
        devices = @r.smembers('all_devices')

        if @ignore_hosts != false
          devices.delete_if { |k| @ignore_hosts.include?(k) }
        end
        #### sooo....
        #### we used to want all hosts on the net. Turns out, we only
        #### want registered hosts...

        # nmap for the win. slow, but awesome.
        # if `which nmap`
        # `nmap -T4 192.168.200.1/24 -n -sP | grep report | awk '{print $5}'`.split("\n").map{|n| begin; devices.add @dns.getname(n); rescue; end}
        #   Parallel.each(nmapping) do |d|
        #     begin
        #       name = @dns.getname(d)
        #       devices.add(name)
        #     rescue Resolv::ResolvError
        #       # can't look it up, router doesn't know it. Static IP.
        #       # moving on.
        #       next
        #     end
        #   end
        # end

        # # arp, for where nmap mysteriously fails or isn't installed (why not?)
        # # speedy, but occasionally deeply innacurrate.
        # `arp -a | grep -v "?" | grep -v "incomplete" | awk '{print $1 }'`.split("\n").each { |d| devices.add(d) }

        # device_names_arr = `for i in {1..254}; do echo ping -c 4 192.168.200.${i} ; done | parallel -j 0 --no-notice 2> /dev/null | awk '/ttl/ { print $4 }' | sort | uniq | sed 's/://' | xargs -n 1 host | awk '{ print $5 }' | awk '!/3\(NXDOMAIN\)/' | sed 's/\.$//'`.split(/\n/)
        # device_names_arr.each do |d|
        #   unless d.match(/Wireless|EPSON/)
        #     device_names_hash[d] = nil
        #   end
        # end

        # ping is low memory and largely io bound.

        f = Parallel.map(devices, in_threads: devices.length) do |device_name|
          begin
            # because if dnsmasq doesn't know about it
            # it isn't a host anymore.

            if @dns.getaddress(device_name) && ping(device_name)
              @r.sadd('current_devices', device_name)
              device_name
            else
              @r.srem('current_devices', device_name)
              nil
            end
          rescue Resolv::ResolvError
            # dnsmasq doesn't know about this device
            # remove from current devices set.
            @r.srem('current_devices', device_name)
            nil
          end
        end
        f.compact!
        puts "found: #{f.to_s}"
        # device_array.compact! # remove nils.
        # # this is uneeded, but need to change the whole process...
        # device_array.map do |a|
        #   device_names_hash[a[0]] = a[1]
        # end

        # # why not communicate directly with redis?
        # begin
        #   url = "http://#{ENV['SERVER_HOST']}:#{ENV['IPORT']}/information"
        #   HTTParty.post(url, query: { devices: device_names_hash.to_json })
        # rescue
        #   puts 'Looks like you might not have the Benevolent Gaze gem running'
        # ensure
        #   device_array, devices, device_names_hash = nil
        # end
      end
    end
  end
end
