## Add an API for reading a request body chunk into an IO (pipe)

      ```ruby
      # currently
      chunk = req.next_chunk
      # or
      req.each_chunk { |c| do_something(c) }

      # what we'd like to do
      r, w = IO.pipe
      len = req.splice_chunk(w)
      sock << "Here comes a chunk of #{len} bytes\n"
      sock.splice(r, len)

      # or:
      r, w = IO.pipe
      req.splice_each_chunk(w) do |len|
        sock << "Here comes a chunk of #{len} bytes\n"
        sock.splice(r, len)
      end
      ```

# HTTP/1.1 parser

- httparser.rb is not actively updated
- the httparser.rb C parser code comes originally from https://github.com/nodejs/llhttp
- there's a Ruby gem https://github.com/metabahn/llhttp, but its API is too low-level
  (lots of callbacks, headers need to be retained across callbacks)
- the basic idea is to import the C-code, then build a parser object with the following
  callbacks:

  ```ruby
  on_headers_complete(headers)
  on_body_chunk(chunk)
  on_message_complete
  ```

- The llhttp gem's C-code is here: https://github.com/metabahn/llhttp/tree/main/mri

- Actually, if you do a C extension, instead of a callback-based API, we can
  design a blocking API:

  ```ruby
  parser = Tipi::HTTP1::Parser.new
  parser.each_request(socket) do |headers|
    request = Request.new(normalize_headers(headers))
    handle_request(request)
  end
  ```

# What about HTTP/2?

It would be a nice exercise in converting a callback-based API to a blocking
one:

```ruby
parser = Tipi::HTTP2::Parser.new(socket)
parser.each_stream(socket) do |stream|
  spin { handle_stream(stream) }
end
```



# DF

- Add attack protection for IP-address HTTP host:

  ```ruby
  IPV4_REGEXP = /^\d+\.\d+\.\d+\.\d+$/.freeze

  def is_attack_request?(req)
    return true if req.host =~ IPV4_REGEXP && req.query[:q] != 'ping'
  end
  ```

- Add attack route to Qeweney routing API



# Roadmap

- Update README (get rid of non-http stuff)
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
