# frozen_string_literal: true

require 'bundler/setup'

require 'fileutils'
require_relative './eg'

require_relative './coverage' if ENV['COVERAGE']

require 'minitest/autorun'
require 'minitest/reporters'

require 'polyphony'

::Exception.__disable_sanitized_backtrace__ = true

Minitest::Reporters.use! [
  Minitest::Reporters::SpecReporter.new
]

class MiniTest::Test
  def setup
    # puts "* setup #{self.name}"
    if Fiber.current.children.size > 0
      puts "Children left: #{Fiber.current.children.inspect}"
      exit!
    end
    Fiber.current.setup_main_fiber
    Fiber.current.instance_variable_set(:@auto_watcher, nil)
    Thread.current.backend = Polyphony::Backend.new
    sleep 0
  end

  def teardown
    # puts "* teardown #{self.name.inspect} Fiber.current: #{Fiber.current.inspect}"
    Fiber.current.terminate_all_children
    Fiber.current.await_all_children
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
end