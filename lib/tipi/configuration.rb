# frozen_string_literal: true

require_relative './handler'

module Tipi
  module Configuration
    class << self
      def supervise_config
        current_runner = nil
        while (config = receive)
          old_runner, current_runner = current_runner, spin { run(config) }
          old_runner&.stop
        end
      end
      
      def run(config)
        start_listeners(config)
        config[:forked] ? forked_supervise(config) : simple_supervise(config)
      end

      def start_listeners(config)
        puts "listening on port 1234"
        @server = Polyphony::Net.tcp_listen('0.0.0.0', 1234, { reuse_addr: true, dont_linger: true })
      end

      def simple_supervise(config)
        virtual_hosts = setup_virtual_hosts(config)
        start_acceptors(config, virtual_hosts)
        suspend
        # supervise(restart: true)
      end
      
      def forked_supervise(config)
        config[:forked].times do
          spin { Polyphony.watch_process { simple_supervise(config) } }
        end
        suspend
      end

      def setup_virtual_hosts(config)
        {
          '*': Tipi::DefaultHandler.new(config)
        }
      end

      def start_acceptors(config, virtual_hosts)
        spin do
          puts "pid: #{Process.pid}"
          while (connection = @server.accept)
            spin { virtual_hosts[:'*'].call(connection) }
          end
        end
      end
    end
  end
end