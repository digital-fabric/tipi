# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'

opts = {
  reuse_addr:  true,
  dont_linger: true
}

puts "pid: #{Process.pid}"
puts 'Listening on port 4411...'

app = Tipi.route do |r|

  r.on_root do
    r.redirect '/hello'
  end
  r.on 'hello' do
    r.on_get 'world' do
      r.respond 'Hello world'
    end
    r.on_get do
      r.respond 'Hello'
    end
    r.on_post do
      puts 'Someone said Hello'
      r.redirect '/'
    end
  end
end

spin do
  Tipi.serve('0.0.0.0', 4411, opts, &app)
end.await
