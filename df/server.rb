# frozen_string_literal: true

require_relative 'server_utils'

spin_loop(interval: 10) { log "Stats: #{Thread.current.fiber_scheduling_stats.inspect}" }

listeners = [
  listen_http,
  listen_https,
  listen_unix
]

begin
  log('Starting DF server')
  Fiber.await(*listeners)
rescue Interrupt
  log('Got SIGINT, shutting down gracefully')
  @service.graceful_shutdown
rescue Exception => e
  log("Uncaught exception", error: e, backtrace: e.backtrace)
ensure
  log('DF server stopped')
end
