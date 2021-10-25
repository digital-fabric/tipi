## 0.45 2021-10-25

- Remove `http_parser.rb` dependency (#14) - thanks @SwagDevOps
- Use `argv` argument in `Tipi.opts_from_argv` (#13) - thanks @SwagDevOps
- Ignore `ArgumentError` in `#parse_headers`

## 0.44 2021-09-29

- Implement compatibility mode for HTTP/1 (WIP)
- Add option parsing for CLI tool
- Implement supervisor-controller-worker model in CLI tool

## 0.43 2021-08-20

- Extract HTTP/1 parser into a separate gem:
  [H1P](https://github.com/digital-fabric/h1p)

## 0.42 2021-08-16

- HTTP/1 parser:  disable UTF-8 parsing for all but header values
- Add support for parsing HTTP/1 from callable source
- Introduce full_service API for automatic HTTPS
- Introduce automatic SSL certificate provisioning
- Improve handling of exceptions
- Various fixes to DF service and agent pxoy
- Fix upgrading to HTTP2 with a request body
- Switch to new HTTP/1 parser

## 0.41 2021-07-26

- Fix Rack adapter (#11)
- Introduce experimental HTTP/1 parser
- More work on DF server
- Allow setting chunk size in `#respond_from_io`

## 0.40 2021-06-24

- Implement serving static files using splice_chunks (nice performance boost for
  files bigger than 1M)
- Call shutdown before closing socket
- Fix examples (thanks @timhatch!)

## 0.39 2021-06-20

- More work on DF server
- Fix HTTP2StreamHandler#send_headers
- Various fixes to HTTP/2 adapter
- Fix host detection for HTTP/2 connections
- Fix HTTP/1 adapter #respond with nil body
- Fix HTTP1Adapter#send_headers

## 0.38 2021-03-09

- Don't use chunked transfer encoding for non-streaming responses

## 0.37.2 2021-03-08

- Fix header formatting when header value is an array

## 0.37 2021-02-15

- Update upgrade mechanism to work with updated Qeweney API

## 0.36 2021-02-12

- Use `Qeweney::Status` constants

## 0.35 2021-02-10

- Extract Request class into separate [qeweney](https://github.com/digital-fabric/qeweney) gem

## 0.34 2021-02-07

- Implement digital fabric service and agents
- Add multipart and urlencoded form data parsing
- Improve request body reading behaviour
- Add more `Request` information methods
- Add access to connection for HTTP2 requests
- Allow calling `Request#send_chunk` with empty chunk
- Add support for handling protocol upgrades from within request handler

## 0.33 2020-11-20

- Update code for Polyphony 0.47.5
- Add support for Rack::File body to Tipi::RackAdapter

## 0.32 2020-08-14

- Respond with array of strings instead of concatenating for HTTP 1
- Use read_loop instead of readpartial
- Fix http upgrade test

## 0.31 2020-07-28

- Fix websocket server code
- Implement configuration layer (WIP)
- Improve performance of rack adapter

## 0.30 2020-07-15

- Rename project to Tipi
- Rearrange source code
- Remove HTTP client code (to be developed eventually into a separate gem)
- Fix header rendering in rack adapter (#2)

## 0.29 2020-07-06

- Use IO#read_loop

## 0.28 2020-07-03

- Update with API changes from Polyphony >= 0.41

## 0.27 2020-04-14

- Remove modulation dependency

## 0.26 2020-03-03

- Fix `Server#listen`

## 0.25 2020-02-19

- Ensure server socket is closed upon stopping loop
- Fix `Request#format_header_lines`

## 0.24 2020-01-08

- Move HTTP to separate polyphony-http gem

For earlier changes look at the Polyphony changelog.
