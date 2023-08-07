# frozen_string_literal: true

require 'polyphony'
require 'json'

module Tipi
  module Supervisor
    class << self
      def run(opts)
        puts "Start supervisor pid: #{Process.pid}"
        @opts = opts
        @controller_watcher = start_controller_watcher
        supervise_loop
      end

      def start_controller_watcher
        spin do
          cmd = controller_cmd
          puts "Starting controller..."
          pid = Kernel.spawn(*cmd)
          @controller_pid = pid
          puts "Controller pid: #{pid}"
          _pid, status = Polyphony.backend_waitpid(pid)
          puts "Controller has terminated with status: #{status.inspect}"
          terminated = true
        ensure
          if pid && !terminated
            puts "Terminate controller #{pid.inspect}"
            Polyphony::Process.kill_process(pid)
          end
          Fiber.current.parent << pid
        end
      end

      def controller_cmd
        [
          'ruby',
          File.join(__dir__, 'controller.rb'),
          @opts.to_json
        ]
      end

      def supervise_loop
        this_fiber = Fiber.current
        trap('SIGUSR2') { this_fiber << :replace_controller }
        loop do
          case (msg = receive)
          when :replace_controller
            replace_controller
          when Integer
            pid = msg
            if pid == @controller_pid
              puts 'Detected dead controller. Restarting...'
              exit!
              @controller_watcher.restart
            end
          else
            raise "Invalid message received: #{msg.inspect}"
          end
        end
      end

      def replace_controller
        puts "Replacing controller"
        old_watcher = @controller_watcher
        @controller_watcher = start_controller_watcher

        # TODO: we'll want to get some kind of signal from the new controller once it's ready
        sleep 1

        old_watcher.terminate(graceful: true)
      end
    end
  end
end
