# frozen_string_literal: true

run { |req|
  req.respond('Hello, world!', 'Content-Type' => 'text/plain')
}
