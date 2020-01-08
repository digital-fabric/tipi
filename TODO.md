# HTTP Client Agent

The concurrency model and the fact that we want to serve the response object on
receiving headers and let the user lazily read the response body, means we'll
need to change the API to accept a block:

```ruby
# current API
resp = Agent.get('http://acme.org')
puts resp.body

# proposed API
Agent.get('http://acme.org') do |resp|
  puts resp.body
end
```

While the block is running, the connection adapter is acquired. Once the block
is done running, the request (and response) can be discarded. The problem with
that if we spin up a coprocess from that block we risk all kinds of race
conditions and weird behaviours.

A compromise might be to allow the two: doing a `get` without providing a block
will return a response object that already has the body (i.e. the entire
response has already been received). Doing a `get` with a block will invoke the
block once headers are received, letting the user's code stream the body:

```ruby
def request(ctx, &block)
  ...
  connection_manager.acquire do |adapter|
    response = adapter.request(ctx)
    if block
      block.(response)
    else
      # wait for body
      response.body
    end
    response
  end
end
```

# Roadmap:

## 0.25 Full Rack adapter implementation

- Work better mechanism supervising multiple coprocesses (`when_done` feels a
  bit hacky)
- Add supervisor test
- Homogenize HTTP 1 and HTTP 2 headers - upcase ? downcase ?
- find some demo Rack apps and test with Polyphony

## 0.26 Working Sinatra application

- app with database access (postgresql)
- benchmarks!

## 0.27 Testing & docs
