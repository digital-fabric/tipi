# frozen_string_literal: true

run lambda { |env|
  [
    200,
    {"Content-Type" => "text/plain"},
    ["Hello, world!"]
  ]
}
