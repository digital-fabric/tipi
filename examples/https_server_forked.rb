# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'localhost/authority'

::Exception.__disable_sanitized_backtrace__ = true

authority = Localhost::Authority.fetch
opts = {
  reuse_addr:     true,
  dont_linger:    true,
  secure_context: authority.server_context
}

server = Tipi.listen('0.0.0.0', 1234, opts)

puts 'Listening on port 1234'

child_pids = []
4.times do
  pid = Polyphony.fork do
    puts "forked pid: #{Process.pid}"
    server.each do |req|
      req.respond("Hello world!\n")
    end
  rescue Interrupt
  end
  child_pids << pid
end

child_pids.each { |pid| Thread.current.backend.waitpid(pid) }
