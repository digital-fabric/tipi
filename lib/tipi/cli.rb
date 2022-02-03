# frozen_string_literal: true

require 'tipi'
require 'fileutils'
require 'tipi/supervisor'
require 'optparse'

module Tipi
  DEFAULT_OPTS = {
    app_type: :web,
    mode: :polyphony,
    workers: 1,
    threads: 1,
    listen: ['http', 'localhost', 1234],
    path: '.',
  }

  def self.opts_from_argv(argv)
    opts = DEFAULT_OPTS.dup
    parser = OptionParser.new do |o|
      o.banner = "Usage: tipi [options] path"
      o.on('-h', '--help', 'Show this help') { puts o; exit }
      o.on('-wNUM', '--workers NUM', 'Number of worker processes (default: 1)') do |v|
        opts[:workers] = v
      end
      o.on('-tNUM', '--threads NUM', 'Number of worker threads (default: 1)') do |v|
        opts[:threads] = v
        opts[:mode] = :stock
      end
      o.on('-c', '--compatibility', 'Use compatibility mode') do
        opts[:mode] = :stock
      end
      o.on('-lSPEC', '--listen SPEC', 'Setup HTTP listener') do |v|
        opts[:listen] = parse_listen_spec('http', v)
      end
      o.on('-sSPEC', '--secure SPEC', 'Setup HTTPS listener (for localhost)') do |v|
        opts[:listen] = parse_listen_spec('https', v)
      end
      o.on('-fSPEC', '--full-service SPEC', 'Setup HTTP/HTTPS listeners (with automatic certificates)') do |v|
        opts[:listen] = parse_listen_spec('full', v)
      end
      o.on('-v', '--verbose', 'Verbose output') do
        opts[:verbose] = true
      end
    end.parse!(argv)
    opts[:path] = argv.shift unless argv.empty?
    verify_path(opts[:path])
    opts
  end

  def self.parse_listen_spec(type, spec)
    [type, *spec.split(':').map { |s| str_to_native_type(s) }]
  end

  def self.str_to_native_type(str)
    case str
    when /^\d+$/
      str.to_i
    else
      str
    end
  end

  def self.verify_path(path)
    return if File.file?(path) || File.directory?(path)

    puts "Invalid path specified #{path}"
    exit!
  end

  module CLI
    BANNER =
      "\n" +
      "         ooo\n" +
      "       oo\n" +
      "     o\n" +
      "   \\|/    Tipi - a better web server for a better world\n" +
      "   / \\       \n" +
      "  /   \\      https://github.com/digital-fabric/tipi\n" +
      "⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺⎺\n"

    def self.start(argv = ARGV.dup)
      opts = Tipi.opts_from_argv(argv)
      display_banner if STDOUT.tty? && !opts[:silent]

      Tipi::Supervisor.run(opts)
    end

    def self.display_banner
      puts BANNER
    end
  end
end
