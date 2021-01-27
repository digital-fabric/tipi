# frozen_string_literal: true

require 'tipi/digital_fabric'
require 'json'

module DigitalFabric
  # agent for managing DF service
  class Executive
    INDEX_HTML = IO.read(File.join(__dir__, 'executive/index.html'))

    attr_reader :last_service_stats

    def initialize(service, route = { path: '/executive' })
      @service = service
      route[:executive] = true
      @service.mount(route, self)
      @current_request_count = 0
      @updater = spin_loop(interval: 10) { update_service_stats }
      update_service_stats
    end

    def current_request_count
      @current_request_count
    end

    def http_request(req)
      @current_request_count += 1
      case req.path
      when '/'
        req.respond(INDEX_HTML, 'Content-Type' => 'text/html')
      when '/stats'
        message = last_service_stats
        req.respond(message.to_json, { 'Content-Type' => 'text.json' })
      when '/stream/stats'
        stream_stats(req)
      else
        req.respond('Invalid path', { ':status' => 404 })
      end
    ensure
      @current_request_count -= 1
    end

    def stream_stats(req)
      req.send_headers({ 'Content-Type' => 'text/event-stream' })
      throttled_loop(interval: 10) do
        message = last_service_stats
        req.send_chunk(format_sse_event(message.to_json))
      end
    # rescue Polyphony::Cancel, Polyphony::Terminate => e
    #   req.finish rescue nil
    rescue IOError, SystemCallError
      # ignore
    end

    def format_sse_event(data)
      "data: #{data}\n\n"
    end

    def update_service_stats
      @last_service_stats = {
        service: @service.stats,
        machine: machine_stats
      }
    end

    TOP_CPU_REGEXP = /%Cpu(.+)/.freeze
    TOP_CPU_IDLE_REGEXP = /([\d\.]+) id/.freeze
    TOP_MEM_REGEXP = /MiB Mem(.+)/.freeze
    TOP_MEM_FREE_REGEXP = /([\d\.]+) free/.freeze
    LOADAVG_REGEXP = /^([\d\.]+)/.freeze

    def machine_stats
      top = `top -bn1`
      unless top =~ TOP_CPU_REGEXP && Regexp.last_match(1) =~ TOP_CPU_IDLE_REGEXP
        p top =~ TOP_CPU_REGEXP
        p Regexp.last_match(1)
        p Regexp.last_match(1) =~ TOP_CPU_IDLE_REGEXP
        raise 'Invalid output from top (cpu)'
      end
      cpu_utilization = 100 - Regexp.last_match(1).to_i
      
      unless top =~ TOP_MEM_REGEXP && Regexp.last_match(1) =~ TOP_MEM_FREE_REGEXP
        raise 'Invalid output from top (mem)'
      end

      mem_free = Regexp.last_match(1).to_f

      stats = `cat /proc/loadavg`
      raise 'Invalid output from /proc/loadavg' unless stats =~ LOADAVG_REGEXP
      load_avg = Regexp.last_match(1).to_f

      {
        mem_free: mem_free,
        cpu_utilization: cpu_utilization,
        load_avg: load_avg
      }
    end
  end
end
