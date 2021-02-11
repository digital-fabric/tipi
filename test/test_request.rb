# frozen_string_literal: true

require_relative 'helper'
require 'tipi'

class String
  def http_lines
    gsub "\n", "\r\n"
  end
end

class IO
  # Creates two mockup sockets for simulating server-client communication
  def self.server_client_mockup
    server_in, client_out = IO.pipe
    client_in, server_out = IO.pipe

    server_connection = mockup_connection(server_in, server_out, client_out)
    client_connection = mockup_connection(client_in, client_out, server_out)

    [server_connection, client_connection]
  end

  def self.mockup_connection(input, output, output2)
    eg(
      :read        => ->(*args) { input.read(*args) },
      :read_loop   => ->(*args, &block) { input.read_loop(*args, &block) },
      :recv_loop   => ->(*args, &block) { input.read_loop(*args, &block) },
      :readpartial => ->(*args) { input.readpartial(*args) },
      :recv        => ->(*args) { input.readpartial(*args) },
      :<<          => ->(*args) { output.write(*args) },
      :write       => ->(*args) { output.write(*args) },
      :close       => -> { output.close },
      :eof?        => -> { output2.closed? }
    )
  end
end

class RequestHeadersTest < MiniTest::Test
  def teardown
    @server&.interrupt if @server&.alive?
    snooze
    super
  end

  def spin_server(opts = {}, &handler)
    server_connection, client_connection = IO.server_client_mockup
    coproc = spin do
      Tipi.client_loop(server_connection, opts, &handler)
    end
    [coproc, client_connection, server_connection]
  end

  def test_request_headers
    req = nil
    @server, connection = spin_server do |r|
      req = r
      req.respond('Hello, world!')
    end

    connection << "GET /titi HTTP/1.1\r\nHost: blah.com\r\nFoo: bar\r\nhi: 1\r\nHi: 2\r\nhi: 3\r\n\r\n"

    snooze

    assert_kind_of Qeweney::Request, req
    assert_equal 'blah.com', req.headers['host']
    assert_equal 'bar', req.headers['foo']
    assert_equal ['1', '3', '2'], req.headers['hi']
    assert_equal 'get', req.headers[':method']
    assert_equal '/titi', req.headers[':path']
  end

  def test_request_host
    req = nil
    @server, connection = spin_server do |r|
      req = r
      req.respond('Hello, world!')
    end

    connection << "GET /titi HTTP/1.1\nHost: blah.com\nFoo: bar\nhi: 1\nHi: 2\nhi: 3\n\n"
    snooze
    assert_equal 'blah.com', req.host
  end

  def test_request_connection
    req = nil
    @server, connection = spin_server do |r|
      req = r
      req.respond('Hello, world!')
    end

    connection << "GET /titi HTTP/1.1\nConnection: keep-alive\nFoo: bar\nhi: 1\nHi: 2\nhi: 3\n\n"
    snooze
    assert_equal 'keep-alive', req.connection
  end

  def test_request_upgrade_protocol
    req = nil
    @server, connection = spin_server do |r|
      req = r
      req.respond('Hello, world!')
    end

    connection << "GET /titi HTTP/1.1\nConnection: upgrade\nUpgrade: foobar\n\n"
    snooze
    assert_equal 'foobar', req.upgrade_protocol
  end
end
