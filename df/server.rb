# frozen_string_literal: true

require_relative 'server_utils'

listeners = [
  listen_http,
  listen_https,
  listen_unix
]

spin_loop(interval: 60) { GC.compact } if GC.respond_to?(:compact)

begin
  log('Starting DF server')
  Fiber.await(*listeners)
rescue Interrupt
  log('Got SIGINT, shutting down gracefully')
  @service.graceful_shutdown
rescue SystemExit
  # ignore
rescue Exception => e
  log("Uncaught exception", error: e, source: e.source_fiber, raising: e.raising_fiber, backtrace: e.backtrace)
ensure
  log('DF server stopped')
end
