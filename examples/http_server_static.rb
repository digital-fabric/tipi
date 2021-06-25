# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'fileutils'

opts = {
  reuse_addr:  true,
  dont_linger: true
}

puts "pid: #{Process.pid}"
puts 'Listening on port 4411...'

root_path = FileUtils.pwd

trap('INT') { exit! }

Tipi.serve('0.0.0.0', 4411, opts) do |req|
  path = File.join(root_path, req.path)
  if File.file?(path)
    req.serve_file(path)
  else
    req.respond(nil, ':status' => Qeweney::Status::NOT_FOUND)
  end
end
