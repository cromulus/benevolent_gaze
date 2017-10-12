require 'resolv'
require 'redis'
require 'hiredis'
require 'parallel'
require 'timeout'
require 'dotenv'
require 'ipaddr'
Dotenv.load if ENV['SLACK_API_TOKEN'].nil?
# must run as root!

module BenevolentGaze
  class Tracker
    def self.run!
      @ignore_hosts = ENV['IGNORE_HOSTS'].nil? ? false : ENV['IGNORE_HOSTS'].split(',')

      @r = Redis.current # right? we've got redis right here.
      @dns = Resolv.new # not sure if we want to re-init resolve.

      # delete all on start
      @r.del('current_devices')
      @r.keys('last_seen:*').each { |key| @r.del(key) }

      # Run forever
      loop do
        do_scan
        sleep 1
      end
    end

    class << self
      private

      # use 240 seconds for phones
      def get_ttl(device)
        device =~ /android|phone/ ? 240 : 60
      end

      # first pings can sometimes fail as
      # the device might be asleep...
      # && in bash will only hit if ping is successfull
      def ping(device)
        begin
          ip = @dns.getaddress(device)
        rescue Resolv::ResolvError
          return false
        end
        cmd = "timeout 0.5 ping -c1 -q #{ip}  > /dev/null 2>&1 && echo true"
        first = exec_with_timeout(cmd, 1).chomp == 'true'
        second = exec_with_timeout(cmd, 1).chomp == 'true'
        first || second # if either hits, we return true
      end

      def add_device(device)
        key = "last_seen:#{device}"
        diff = Time.now.to_i - @r.get(key).to_i
        @r.set(key, Time.now.to_i)
        if diff >= 30 && !@r.sismember('current_devices', device)
          @r.sadd('current_devices', device)
          @r.publish('devices.add', device)
          puts "added: #{device}"
          true
        else
          false
        end
      end

      def remove_device(device)
        key = "last_seen:#{device}"
        diff = Time.now.to_i - @r.get(key).to_i
        if diff >= get_ttl(device) && @r.sismember('current_devices', device)
          @r.srem('current_devices', device)
          @r.publish('devices.remove', device)
          puts "removed device: #{device}"
          true
        else
          false
        end
      end

      # https://stackoverflow.com/questions/8292031/ruby-timeouts-and-system-commands
      def exec_with_timeout(cmd, timeout)
        begin
          # stdout, stderr pipes
          rout, wout = IO.pipe
          rerr, werr = IO.pipe
          stdout, stderr = nil

          pid = Process.spawn(cmd, pgroup: true, out: wout, err: werr)

          Timeout.timeout(timeout) do
            Process.waitpid(pid)

            # close write ends so we can read from them
            wout.close
            werr.close

            stdout = rout.readlines.join
            stderr = rerr.readlines.join
          end
        rescue Timeout::Error
          Process.kill(-9, pid) rescue Errno::ESRCH
          Process.detach(pid) rescue Errno::ESRCH
        ensure
          wout.close unless wout.closed?
          werr.close unless werr.closed?
          # dispose the read ends of the pipes
          rout.close
          rerr.close
        end
        stdout
      end

      # ping is low memory and largely io bound.
      def do_scan
        devices = @r.smembers('all_devices')
        devices.delete_if { |k| @ignore_hosts.include?(k) } if @ignore_hosts

        Parallel.map(devices, in_threads: devices.length) do |device|
          if ping(device)
            add_device(device)
          else
            remove_device(device)
          end
        end
      end
    end
  end
end
