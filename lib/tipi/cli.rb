# frozen_string_literal: true

require 'tipi'
require 'fileutils'
require 'tipi/supervisor'

module Tipi
  ARGV_SINGLE_DASH_REGEXP = /^(\-\w)(.+)?$/.freeze

  def self.shift_argv(argv)
    part = argv.shift
    return nil unless part

    if (m = part.match(ARGV_SINGLE_DASH_REGEXP))
      opt, rest = m[1..2]
      argv.unshift(rest) if rest
      opt
    else
      part
    end
  end

  DEFAULT_OPTS = {
    mode: :polyphony,
    workers: 1,
    threads: 1,
    path: '.',
  }

  HELP = <<~EOF
    tipi <options> <PATH>
        -c, --compat        Turn on compatibility mode (don't load Polyphony)
        -h, --help          Display this message
        -r, --rack PATH     Run a rack app
        -s, --silent        Turn on silent mode
        -t, --threads NUM   Set number of threads per worker
        -v, --verbose       Turn on verbose mode
        -w, --workers NUM   Set number of workers
  EOF

  def self.opts_from_argv(argv)
    opts = DEFAULT_OPTS.dup
    while (part = shift_argv(argv))
      case part
      when '-c', '--compat'
        opts[:mode] = :stock
      when '-h', '--help'
        puts HELP
        exit!
      when '-r', '--rack'
        opts[:rack_app] = shift_argv(argv)
      when '-s', '--silent'
        opts[:silent] = true
      when '-t', '--threads'
        opts[:threads] = shift_argv(argv)
      when '-v', '--verbose'
        opts[:verbose] = true
      when '-w', '--workers'
        opts[:workers] = shift_argv(argv)
      else
        opts[:path] = part
      end
    end
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
