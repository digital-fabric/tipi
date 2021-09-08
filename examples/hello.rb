# frozen_string_literal: true

def app
  ->(req) { req.respond('Hello, world!', 'Content-Type' => 'text/plain') }
end
