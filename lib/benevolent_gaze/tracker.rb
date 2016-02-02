require 'resolv'
require 'httparty'

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
      if ($?.exitstatus == 0) do
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
=begin
      # Look for the network broadcast address
      broadcast = `ifconfig -a | grep broadcast`.split[-1]

      # puts "Broadcast Address #{broadcast}"
      unless broadcast =~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/
        puts "#{broadcast} doesn't look correct"
        exit 1
      end

      # Ping the broadcast address 4 times and wait for responses
      ips = `ping -t 4 #{broadcast}`.split(/\n/).collect do |x|
        if x =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):/
          $1
        else
          nil
        end
      end.select { |x| x && x != broadcast}.sort.uniq

      dns = Resolv.new
      device_names_and_ip_addresses = {}

      ips.each do |ip|
        name = dns.getname ip
        device_names_and_ip_addresses[name] = nil
      end
      puts "****************************"
=end

      #reintroduction of arp usage for mac addresses - will reintegrate soon.
      dns = Resolv.new
      device_names_hash = {}
      device_name_and_mac_address_hash = {}
      `arp -a | grep -v "?" | awk '{print $1 "\t" $4}'`.split("\n").each do |a|
        a = a.split("\t")
        ip_address = dns.getaddress(a[0])

        if ping(ip_address)
          device_name_and_mac_address_hash[a[0]] = a[1]
          device_names_hash[a[0]]=a[1]
        end
      end


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
