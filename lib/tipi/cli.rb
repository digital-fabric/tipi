# frozen_string_literal: true

require 'tipi'
require 'fileutils'
require 'tipi/supervisor'
require 'optparse'

module Tipi
  DEFAULT_OPTS = {
    mode: :polyphony,
    workers: 1,
    threads: 1,
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
        opts[:listen] = parse_listen_spec('https', v)
      end
      o.on('-v', '--verbose', 'Verbose output') do
        opts[:verbose] = true
      end
    end.parse!
    opts[:path] = ARGV.shift unless ARGV.empty?
    opts[:app_type] = detect_app_type(opts)
    opts
  end

  def self.detect_app_type(opts)
    path = opts[:path]
    if File.file?(path)
      File.extname(path) == '.ru' ? :web : :bare
    elsif File.directory?(opts[:path])
      :web
    else
      puts "Invalid path specified #{opts[:path]}"
      exit!
    end
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
