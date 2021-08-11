# frozen_string_literal: true

require 'bundler/setup'
require 'tipi'
require 'tipi/acme'

::Exception.__disable_sanitized_backtrace__ = true

app = ->(r) { r.respond('Hello, world!') }
certificate_db_path = File.expand_path('certificate_store.db', __dir__)
Tipi.full_service(
  certificate_store: Tipi::ACME::SQLiteCertificateStore.new(certificate_db_path),
  app: app
)
