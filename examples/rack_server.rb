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

puts 'listening on port 1234'
puts "pid: #{Process.pid}"
Tipi.serve('0.0.0.0', 1234, opts, &app)
