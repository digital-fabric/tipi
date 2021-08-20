# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'

app_path = ARGV.first || File.expand_path('./config.ru', __dir__)
unless File.file?(app_path)
  STDERR.puts "Please provide rack config file (there are some in the examples directory.)"
  exit!
end

app = Tipi::RackAdapter.load(app_path)
opts = { reuse_addr: true, dont_linger: true }

server = Tipi.listen('0.0.0.0', 1234, opts)
puts 'listening on port 1234'

child_pids = []
4.times do
  child_pids << Polyphony.fork do
    puts "forked pid: #{Process.pid}"
    server.each(&app)
  end
end

child_pids.each { |pid| Thread.current.backend.waitpid(pid) }