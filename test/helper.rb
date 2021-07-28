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

