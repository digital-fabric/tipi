# frozen_string_literal: true

require 'tipi'
require 'fileutils'

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
        opts[:compatible_mode] = true
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
    opts
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
      if File.file?(opts[:path])
        start_app(opts)
      elsif File.directory?(opts[:path])
        start_static_server(opts)
      else
        puts "Invalid path specified #{opts[:path]}"
        exit!
      end
    end

    def self.start_app(opts)
      if File.extname(opts[:path]) == '.ru'
        start_rack_app(opts)
      else
        require(opts[:path])
      end
    end

    def self.start_rack_app(opts)
      app = Tipi::RackAdapter.load(opts[:path])
      serve_app(app, opts)
    end

    def self.display_banner
      puts BANNER
    end

    def self.start_static_server(opts)
      path = opts[:path]
      app = proc do |req|
        full_path = find_path(path, req.path)
        if full_path
          req.serve_file(full_path)
        else
          req.respond(nil, ':status' => Qeweney::Status::NOT_FOUND)
        end
      end
      serve_app(app, opts)
    end

    def self.serve_app(app, opts)
      Tipi.full_service(&app)
    end

    INVALID_PATH_REGEXP = /\/?(\.\.|\.)\//

    def self.find_path(base, path)
      p find_path: [base, path]
      return nil if path =~ INVALID_PATH_REGEXP

      full_path = File.join(base, path)
      return full_path if File.file?(full_path)
      return find_path(full_path, 'index') if File.directory?(full_path)

      qualified = "#{full_path}.html"
      return qualified if File.file?(qualified)

      nil
    end

    def self.supervise(opts)

    end
  end
end
