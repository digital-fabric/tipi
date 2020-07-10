# Roadmap

- Update README (get rid of non-http stuff)
- Improve Rack spec compliance, add tests
- Homogenize HTTP 1 and HTTP 2 headers - upcase ? downcase ?

## 0.30

- Add more poly CLI commands and options:

  - serve static files from given directory
  - serve from rack up file
  - serve both http and https
  - use custom certificate files for SSL
  - set host address to bind to
  - set port to bind to
  - set forking process count

## 0.31 Working Sinatra application

- app with database access (postgresql)
- benchmarks!

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

