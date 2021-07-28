# frozen_string_literal: true

module Tipi
  HTTP1_LIMITS = {
    max_method_length:                       16,
    max_path_length:                         4096,
    max_header_key_length:                   128,
    max_header_value_length:                 2048,
    max_header_count:                        256,
    max_chunked_encoding_chunk_size_length:  16,
  }
end
