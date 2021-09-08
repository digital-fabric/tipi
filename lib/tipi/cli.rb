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
      o.on('-h', '--help') { puts o; exit }
      o.on('-wNUM', '--workers NUM', 'Number of worker processes') do |v|
        opts[:workers] = v
      end
      o.on('-tNUM', '--threads NUM', 'Number of worker threads') do |v|
        opts[:workers] = v
      end
      o.on('-lSPEC', '--listen SPEC', 'Listen spec (HTTP)') do |v|
        opts[:listen] = parse_listen_spec('http', v)
      end
      o.on('-sSPEC', '--secure SPEC', 'Listen spec (HTTPS)') do |v|
        opts[:listen] = parse_listen_spec('https', v)
      end
      o.on('-fSPEC', '--full-service SPEC', 'Listen spec (HTTP+HTTPS)') do |v|
        opts[:listen] = parse_listen_spec('full', v)
      end
      o.on('-v', '--verbose', 'Verbose output') do
        opts[:verbose] = true
      end
    end.parse!
    opts[:path] = ARGV.shift unless ARGV.empty?
    verify_path(opts[:path])
    opts
  end

  def self.parse_listen_spec(type, spec)
    [type, *spec.split(':')]
  end

  def self.verify_path(path)
    return if File.file?(path) || File.directory?(path)

    puts "Invalid path specified #{opts[:path]}"
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

    def self.start
      opts = Tipi.opts_from_argv(ARGV)
      display_banner if STDOUT.tty? && !opts[:silent]
      
      Tipi::Supervisor.run(opts)
    end

    def self.display_banner
      puts BANNER
    end
  end
end
