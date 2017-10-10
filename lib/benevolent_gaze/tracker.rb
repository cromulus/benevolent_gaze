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
        # must run as root! (maybe)
        # or makes sense here, actually. first pings can sometimes fail as
        # the device might be asleep...
        # && in bash will only hit if ping is successfull
        cmd = "timeout 0.5 ping -c1 -q #{host}  > /dev/null 2>&1 && echo true"
        a = exec_with_timeout(cmd, 1).chomp == 'true'
        b = exec_with_timeout(cmd, 1).chomp == 'true'

        a || b # if either hits, we return true
      end

      # setex vs set current timestamp and diff?
      def add_device(device)
        key = "last_seen:#{device}"
        unless @r.exists(key)
          @r.publish('devices.add', device)
          puts "added: #{device}"
        end
        @r.set(key, Time.now.to_i)
        @r.sadd('current_devices', device)
        device
      end

      # if expire exists, do not remove, else remove
      def remove_device(device)
        key = "last_seen:#{device}"
        if @r.exists(key)
          diff = Time.now.to_i - @r.get(key).to_i
          unless diff >= 30 # 30 seconds
            @r.srem('current_devices', device)
            @r.publish('devices.remove', device)
            puts "removed device: #{device}"
          end
        end
        false
      end

      # https://stackoverflow.com/questions/8292031/ruby-timeouts-and-system-commands
      def exec_with_timeout(cmd, timeout)
        begin
          # stdout, stderr pipes
          rout, wout = IO.pipe
          rerr, werr = IO.pipe
          stdout, stderr = nil

          pid = Process.spawn(cmd, pgroup: true, :out => wout, :err => werr)

          Timeout.timeout(timeout) do
            Process.waitpid(pid)

            # close write ends so we can read from them
            wout.close
            werr.close

            stdout = rout.readlines.join
            stderr = rerr.readlines.join
          end

        rescue Timeout::Error
          Process.kill(-9, pid)
          Process.detach(pid)
        ensure
          wout.close unless wout.closed?
          werr.close unless werr.closed?
          # dispose the read ends of the pipes
          rout.close
          rerr.close
        end
        stdout
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
              add_device(device_name)
            else
              remove_device(device_name)
            end
          rescue Resolv::ResolvError
            # dnsmasq doesn't know about this device
            # remove from current devices set.
            remove_device(device_name)
            nil
          end
        end
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
