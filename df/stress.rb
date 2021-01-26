# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'fileutils'

FileUtils.cd(__dir__)

def monitor_process(cmd)
  while true
    puts "Starting #{cmd}"
    Polyphony::Process.watch(cmd)
    sleep 5
  end
end

puts "pid: #{Process.pid}"
puts 'Starting stress test'

spin { monitor_process('ruby server.rb') }
spin { monitor_process('ruby multi_agent_supervisor.rb') }
spin { monitor_process('ruby multi_client.rb') }

sleep
