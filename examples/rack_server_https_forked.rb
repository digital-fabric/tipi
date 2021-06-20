# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'localhost/authority'

app_path = ARGV.first || File.expand_path('./config.ru', __dir__)
app = Tipi::RackAdapter.load(app_path)

authority = Localhost::Authority.fetch
opts = {
  reuse_addr:     true,
  reuse_port:     true,
  dont_linger:    true,
  secure_context: authority.server_context
}
server = Tipi.listen('0.0.0.0', 1234, opts)
puts 'Listening on port 1234'

child_pids = []
4.times do
  child_pids << Polyphony.fork do
    puts "forked pid: #{Process.pid}"
    server.each(&app)
  end
end

child_pids.each { |pid| Thread.current.backend.waitpid(pid) }