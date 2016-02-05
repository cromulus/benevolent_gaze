require 'resolv'
require 'httparty'
require 'parallel'
require 'set'

module BenevolentGaze
  class Tracker
    @@old_time = Time.now.to_i

    def self.run!
      # Run forever
      while true
        scan
        check_time
        sleep 10
      end
    end

  class << self
    private

    def ping(host)
      result = `ping -q -i 0.2 -c 2 #{host}`
      if ($?.exitstatus == 0)
        return true
      else
        return false
      end
    end

    def check_time
      #if ((@@old_time + (30*60)) <= Time.now.to_i)
      if (@@old_time <= Time.now.to_i)
        begin
          #TODO make sure to change the url to read from an environment variable for the correct company url.
        HTTParty.post( (ENV['BG_COMPANY_URL'] || 'http://localhost:3000/register'), query: { ip: `ifconfig | awk '/inet/ {print $2}' | grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" | grep -v 127.0.0.1 | tail -1`.strip + ":#{ENV['IPORT']}/register"})
        puts "Just sent localhost address to server."
        rescue
          puts "Looks like there is something wrong with the endpoint to identify the localhost."
        end
        @old_time = Time.now.to_i
      end
    end

    def scan

      dns = Resolv.new
      device_names_hash = {}
      device_name_and_mac_address_hash = {}
      devices = Set.new # because dupes suck

      #nmap for the win. slow, but awesome.
      if `which nmap`
        `nmap -A -T4 192.168.200.1/24 -n -sP | grep report | awk '{print $5}'`.split("\n").each{|d|
          begin
            name = dns.getname(d)
            devices.add(name)
          rescue Exception
            # can't look it up, router doesn't know it. Static IP.
            # moving on.
            next
          end
        }
      end

      # arp, for where nmap mysteriously fails or isn't installed (why not?)
      # speedy, but occasionally deeply innacurrate.
      `arp -a | grep -v "?" | grep -v "incomplete" | awk '{print $1 }'`.split("\n").each{|d| devices.add(d)}

      #ping is low memory and largely io bound.
      device_array = Parallel.map(devices,:in_threads => devices.length) do |name|
        begin

          ip = dns.getaddress(name)
          #pinging IP.
          result = `ping -q -i 0.2 -c 3 #{ip}`
          result = nil
          # next if ping fails, meaning exitstatus !=0
          next if ($?.exitstatus != 0)

        rescue Exception
          # means we either can't ping, or getAddress failed
          # and router doesn't no about the machine.
          next
        end
        [name,ip]
      end

      device_array.compact! # remove nils.

      device_array.map{|a|
        device_name_and_mac_address_hash[a[0]] = a[1]
        device_names_hash[a[0]]=a[1]
      }

      # device_names_arr = `for i in {1..254}; do echo ping -c 4 192.168.200.${i} ; done | parallel -j 0 --no-notice 2> /dev/null | awk '/ttl/ { print $4 }' | sort | uniq | sed 's/://' | xargs -n 1 host | awk '{ print $5 }' | awk '!/3\(NXDOMAIN\)/' | sed 's/\.$//'`.split(/\n/)
      # device_names_arr.each do |d|
      #   unless d.match(/Wireless|EPSON/)
      #     device_names_hash[d] = nil
      #   end
      # end

      begin
        HTTParty.post("http://localhost:#{ENV['IPORT']}/information", query: {devices: device_names_hash.to_json } )
      rescue
        puts "Looks like you might not have the Benevolent Gaze gem running"
      end
    end
  end
  end
end