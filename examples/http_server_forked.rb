# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'

::Exception.__disable_sanitized_backtrace__ = true

opts = {
  reuse_addr:  true,
  reuse_port: true,
  dont_linger: true
}

child_pids = []
8.times do
  pid = Polyphony.fork do
    puts "forked pid: #{Process.pid}"
    Tipi.serve('0.0.0.0', 1234, opts) do |req|
      req.respond("Hello world! from pid: #{Process.pid}\n")
    end
  rescue Interrupt
  end
  child_pids << pid
end

puts 'Listening on port 1234'

child_pids.each { |pid| Thread.current.backend.waitpid(pid) }
