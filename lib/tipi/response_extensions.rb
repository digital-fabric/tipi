# frozen_string_literal: true

require 'qeweney/request'

module Tipi
  module ResponseExtensions
    SPLICE_CHUNKS_SIZE_THRESHOLD = 2**20

    def serve_io(io, opts)
      if !opts[:stat] || opts[:stat].size >= SPLICE_CHUNKS_SIZE_THRESHOLD
        @adapter.respond_from_io(self, io, opts[:headers], opts[:chunk_size] || 2**14)
      else  
        respond(io.read, opts[:headers] || {})
      end
    end
  end
end
