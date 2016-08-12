require 'resolv'
require 'redis'
require 'httparty'
require 'parallel'
require 'set'
require 'net/ping'

module BenevolentGaze
  class Tracker
    def self.run!
      # Run forever
      loop do
        @r ||= Redis.current
        @dns = Resolv.new
        scan
        # check_time # not sure we need this.
        sleep 1
      end
    end

    class << self
      private

      def ping(host)
        p = Net::Ping::External.new(host,timeout: 1)
        # or makes sense here, actually. first pings can sometimes fail as
        # the device might be asleep...
        res = p.ping? or p.ping? or p.ping?
        res
      end


      def scan

        device_names_hash = {}
        devices = Set.new # because dupes suck

        #### sooo....
        #### we used to want all hosts on the net. Turns out, we only
        #### want registered hosts...

        # nmap for the win. slow, but awesome.
        # if `which nmap`
        #   nmapping = `nmap -T4 192.168.200.1/24 -n -sP | grep report | awk '{print $5}'`.split("\n")
        #   Parallel.each(nmapping) do |d|
        #     begin
        #       name = dns.getname(d)
        #       devices.add(name)
        #     rescue Exception
        #       # can't look it up, router doesn't know it. Static IP.
        #       # moving on.
        #       next
        #     end
        #   end
        # end

        # arp, for where nmap mysteriously fails or isn't installed (why not?)
        # speedy, but occasionally deeply innacurrate.
        # `arp -a | grep -v "?" | grep -v "incomplete" | awk '{print $1 }'`.split("\n").each { |d| devices.add(d) }

        # so, we don't want ALL ip on net, just registered ones.
        # this could also be a request to to the web service too...
        @r.keys('slack:*').map { |k| devices.add k.gsub('slack:', '') }

        # ping is low memory and largely io bound.
        n = devices.length
        device_array = Parallel.map(devices, in_threads: n) do |name|
          begin
            # because if dnsmasq doesn't know about it
            # it isn't a host anymore.
            ip = @dns.getaddress(name)
          rescue Resolv::ResolvError
            next
          end

          # next if ping fails
          next unless ping(ip)

          [name, ip]
        end

        device_array.compact! # remove nils.

        device_array.map do|a|
          device_names_hash[a[0]] = a[1]
        end

        # device_names_arr = `for i in {1..254}; do echo ping -c 4 192.168.200.${i} ; done | parallel -j 0 --no-notice 2> /dev/null | awk '/ttl/ { print $4 }' | sort | uniq | sed 's/://' | xargs -n 1 host | awk '{ print $5 }' | awk '!/3\(NXDOMAIN\)/' | sed 's/\.$//'`.split(/\n/)
        # device_names_arr.each do |d|
        #   unless d.match(/Wireless|EPSON/)
        #     device_names_hash[d] = nil
        #   end
        # end

        begin
          HTTParty.post("http://localhost:#{ENV['IPORT']}/information", query: { devices: device_names_hash.to_json })
        rescue
          puts 'Looks like you might not have the Benevolent Gaze gem running'
        end
      end
    end
  end
end
