# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'

opts = {
  reuse_addr:  true,
  dont_linger: true
}

puts "pid: #{Process.pid}"
puts 'Listening on port 4411...'

spin_loop(interval: 10) { p Thread.current.fiber_scheduling_stats }

spin do
  Tipi.serve('0.0.0.0', 4411, opts) do |req|
    if req.path == '/stream'
      req.send_headers('Foo' => 'Bar')
      sleep 1
      req.send_chunk("foo\n")
      sleep 1
      req.send_chunk("bar\n")
      req.finish
    else
      req.respond("Hello world!\n")
    end
    p req.transfer_counts
  end
  p 'done...'
end.await
