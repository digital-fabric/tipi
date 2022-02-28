# frozen_string_literal: true

run { |req|
  req.send_headers('Content-Type' => 'text/event-stream')
  10.times { |i|
    sleep 0.1
    req.send_chunk("data: #{i.to_s * 40}\n")
  }
  req.finish
}
