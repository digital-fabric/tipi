# frozen_string_literal: true

require 'bundler/setup'

require 'fileutils'
require_relative './eg'

require_relative './coverage' if ENV['COVERAGE']

require 'minitest/autorun'
require 'minitest/reporters'

require 'polyphony'

::Exception.__disable_sanitized_backtrace__ = true

class MiniTest::Test
  def setup
    # trace "* setup #{self.name}"
    if Fiber.current.children.size > 0
      trace "Children left: #{Fiber.current.children.inspect}"
      exit!
    end
    Fiber.current.setup_main_fiber
    Fiber.current.instance_variable_set(:@auto_watcher, nil)
    Thread.current.backend = Polyphony::Backend.new
    sleep 0
  end

  def teardown
    # trace "* teardown #{self.name}"
    Fiber.current.shutdown_all_children
  rescue => e
    puts e
    puts e.backtrace.join("\n")
    exit!
  end
end

module Kernel
  def capture_exception
    yield
  rescue Exception => e
    e
  end

  def trace(*args)
    STDOUT.orig_write(format_trace(args))
  end

  def format_trace(args)
    if args.first.is_a?(String)
      if args.size > 1
        format("%s: %p\n", args.shift, args)
      else
        format("%s\n", args.first)
      end
    else
      format("%p\n", args.size == 1 ? args.first : args)
    end
  end
end

class IO
  # Creates two mockup sockets for simulating server-client communication
  def self.server_client_mockup
    server_in, client_out = IO.pipe
    client_in, server_out = IO.pipe

    server_connection = mockup_connection(server_in, server_out, client_out)
    client_connection = mockup_connection(client_in, client_out, server_out)

    [server_connection, client_connection]
  end

  def self.mockup_connection(input, output, output2)
    eg(
      __polyphony_read_method__: ->() { :readpartial },
      read:         ->(*args) { input.read(*args) },
      read_loop:    ->(*args, &block) { input.read_loop(*args, &block) },
      recv_loop:    ->(*args, &block) { input.read_loop(*args, &block) },
      readpartial:  ->(*args) { input.readpartial(*args) },
      recv:         ->(*args) { input.readpartial(*args) },
      '<<':         ->(*args) { output.write(*args) },
      write:        ->(*args) { output.write(*args) },
      close:        -> { output.close },
      eof?:         -> { output2.closed? }
    )
  end
end

module Minitest::Assertions
  def assert_in_range exp_range, act
    msg = message(msg) { "Expected #{mu_pp(act)} to be in range #{mu_pp(exp_range)}" }
    assert exp_range.include?(act), msg
  end
end
