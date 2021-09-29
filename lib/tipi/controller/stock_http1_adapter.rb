# frozen_string_literal: true

require 'tipi/http1_adapter'

module Tipi
  class StockHTTP1Adapter < HTTP1Adapter
    def initialize(conn, opts)
      super(conn, opts)

    end

    def each(&block)
    end
  end
end