# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'

opts = {
  reuse_addr:  true,
  dont_linger: true
}

puts "pid: #{Process.pid}"
puts 'Listening on port 4411...'

app = Tipi.route do |req|
  req.on 'stream' do
    req.send_headers('Foo' => 'Bar')
    sleep 1
    req.send_chunk("foo\n")
    sleep 1
    req.send_chunk("bar\n")
    req.finish
  end
  req.default do
    req.respond("Hello world!\n")
  end
end

trap('INT') { exit! }
Tipi.serve('0.0.0.0', 4411, opts, &app)
