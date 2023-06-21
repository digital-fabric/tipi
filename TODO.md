## Rethink design

- Remove DF code
- Remove non-Polyphony code

# Miscellaneous

- Try using `TCP_DEFER_ACCEPT` with Polyphony on io_uring - does it provide any
  performance benefit?

# What about HTTP/2?

It would be a nice exercise in converting a callback-based API to a blocking
one:

```ruby
parser = Tipi::HTTP2::Parser.new(socket)
parser.each_stream(socket) do |stream|
  spin { handle_stream(stream) }
end
```


# Roadmap

- Improve Rack spec compliance, add tests
- Homogenize HTTP 1 and HTTP 2 headers - downcase symbols

- Use `http-2-next` instead of `http-2` for http/2
  - https://gitlab.com/honeyryderchuck/http-2-next
  - Open an issue there, ask what's the difference between the two gems?

## 0.38

- Add more poly CLI commands and options:

  - serve static files from given directory
  - serve from rack up file
  - serve both http and https
  - use custom certificate files for SSL
  - set host address to bind to
  - set port to bind to
  - set forking process count

## 0.39 Working Sinatra application

- app with database access (postgresql)
- benchmarks!
