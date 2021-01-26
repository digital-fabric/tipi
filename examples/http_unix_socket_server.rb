# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'

path = '/tmp/tipi.sock'

puts "pid: #{Process.pid}"
puts "Listening on #{path}"

FileUtils.rm(path) rescue nil
socket = UNIXServer.new(path)
Tipi.accept_loop(socket, {}) do |req|
  req.respond("Hello world!\n")
rescue Exception => e
  p e
end
