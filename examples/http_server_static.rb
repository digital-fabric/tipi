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

app = Tipi.route do |req|
  req.on('normal') do
    path = File.join(root_path, req.route_relative_path)
    if File.file?(path)
      req.serve_file(path)
    else
      req.respond(nil, ':status' => Qeweney::Status::NOT_FOUND)
    end
  end
  req.on('spliced') do
    path = File.join(root_path, req.route_relative_path)
    if File.file?(path)
      req.serve_file(path, respond_from_io: true)
    else
      req.respond(nil, ':status' => Qeweney::Status::NOT_FOUND)
    end
  end
end

Tipi.serve('0.0.0.0', 4411, opts, &app)
