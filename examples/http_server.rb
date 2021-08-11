# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'

opts = {
  reuse_addr:  true,
  dont_linger: true
}

puts "pid: #{Process.pid}"
puts 'Listening on port 10080...'

# GC.disable
# Thread.current.backend.idle_gc_period = 60

spin_loop(interval: 10) { p Thread.backend.stats }

spin_loop(interval: 10) do
  GC.compact
end

spin do
  Tipi.serve('0.0.0.0', 10080, opts) do |req|
    if req.path == '/stream'
      req.send_headers('Foo' => 'Bar')
      sleep 1
      req.send_chunk("foo\n")
      sleep 1
      req.send_chunk("bar\n")
      req.finish
    elsif req.path == '/upload'
      body = req.read
      req.respond("Body: #{body.inspect} (#{body.bytesize} bytes)")
    else
      req.respond("Hello world!\n")
    end
#    p req.transfer_counts
  end
  p 'done...'
end.await
