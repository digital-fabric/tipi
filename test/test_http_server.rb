# frozen_string_literal: true

require_relative 'helper'
require 'tipi'

class String
  def crlf_lines
    gsub "\n", "\r\n"
  end
end

class HTTP1ServerTest < MiniTest::Test
  def teardown
    @server&.interrupt if @server&.alive?
    sleep 0.01
    super
  end

  def spin_server(opts = {}, &handler)
    server_connection, client_connection = IO.server_client_mockup
    coproc = spin do
      Tipi.client_loop(server_connection, opts, &handler)
    end
    [coproc, client_connection, server_connection]
  end

  def test_that_server_uses_content_length_in_http_1_0
    @server, connection = spin_server do |req|
      req.respond('Hello, world!', {})
    end

    # using HTTP 1.0, server should close connection after responding
    connection << "GET / HTTP/1.0\r\n\r\n"

    response = connection.readpartial(8192)
    expected = <<~HTTP.chomp.crlf_lines.chomp
      HTTP/1.1 200 OK
      Content-Length: 13

      Hello, world!
    HTTP
    assert_equal(expected, response)
  end

  def test_that_server_uses_chunked_encoding_in_http_1_1
    @server, connection = spin_server do |req|
      req.respond('Hello, world!')
    end

    # using HTTP 1.0, server should close connection after responding
    connection << "GET / HTTP/1.1\r\n\r\n"

    response = connection.readpartial(8192)
    expected = <<~HTTP.crlf_lines.chomp
      HTTP/1.1 200 OK
      Content-Length: 13

      Hello, world!
    HTTP
    assert_equal(expected, response)
  end

  def test_that_server_maintains_connection_when_using_keep_alives
    @server, connection = spin_server do |req|
      req.respond('Hi', {})
    end

    connection << "GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n"
    response = connection.readpartial(8192)
    sleep 0.01
    assert !connection.eof?
    assert_equal("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nHi", response)

    connection << "GET / HTTP/1.1\r\n\r\n"
    response = connection.readpartial(8192)
    sleep 0.01
    assert !connection.eof?
    expected = <<~HTTP.crlf_lines.chomp
      HTTP/1.1 200 OK
      Content-Length: 2

      Hi
    HTTP
    assert_equal(expected, response)

    connection << "GET / HTTP/1.0\r\n\r\n"
    response = connection.readpartial(8192)
    sleep 0.01
    assert connection.eof?
    assert_equal("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nHi", response)
  end

  def test_pipelining_client
    @server, connection = spin_server do |req|
      if req.headers['foo'] == 'bar'
        req.respond('Hello, foobar!', {})
      else
        req.respond('Hello, world!', {})
      end
    end

    connection << "GET / HTTP/1.1\r\n\r\nGET / HTTP/1.1\r\nFoo: bar\r\n\r\n"
    sleep 0.01
    response = connection.readpartial(8192)

    expected = <<~HTTP.crlf_lines.chomp
      HTTP/1.1 200 OK
      Content-Length: 13

      Hello, world!HTTP/1.1 200 OK
      Content-Length: 14

      Hello, foobar!
    HTTP
    assert_equal(expected, response)
  end

  def test_body_chunks
    chunks = []
    request = nil
    @server, connection = spin_server do |req|
      request = req
      req.send_headers
      req.each_chunk do |c|
        chunks << c
        req << c.upcase
      end
      req.finish
    end

    connection << <<~HTTP.crlf_lines
      POST / HTTP/1.1
      Transfer-Encoding: chunked

      6
      foobar
    HTTP
    sleep 0.01
    assert request
    assert_equal %w[foobar], chunks
    assert !request.complete?

    connection << "6\r\nbazbud\r\n"
    sleep 0.01
    assert_equal %w[foobar bazbud], chunks
    assert !request.complete?

    connection << "0\r\n\r\n"
    sleep 0.01
    assert_equal %w[foobar bazbud], chunks
    assert request.complete?

    sleep 0.01

    response = connection.readpartial(8192)

    expected = <<~HTTP.crlf_lines
      HTTP/1.1 200
      Transfer-Encoding: chunked

      6
      FOOBAR
      6
      BAZBUD
      0

    HTTP
    assert_equal(expected, response)
  end

  def test_upgrade
    done = nil

    opts = {
      upgrade: {
        echo: lambda do |adapter, _headers|
          conn = adapter.conn
          conn << <<~HTTP.crlf_lines
            HTTP/1.1 101 Switching Protocols
            Upgrade: echo
            Connection: Upgrade

          HTTP

          conn.read_loop { |data| conn << data }
          done = true
        end
      }
    }

    @server, connection = spin_server(opts) do |req|
      req.respond('Hi')
    end

    connection << "GET / HTTP/1.1\r\n\r\n"
    response = connection.readpartial(8192)
    sleep 0.01
    assert !connection.eof?
    expected = <<~HTTP.crlf_lines.chomp
      HTTP/1.1 200 OK
      Content-Length: 2

      Hi
    HTTP
    assert_equal(expected, response)

    connection << <<~HTTP.crlf_lines
      GET / HTTP/1.1
      Upgrade: echo
      Connection: upgrade

    HTTP

    snooze
    response = connection.readpartial(8192)
    snooze
    assert !connection.eof?
    expected = <<~HTTP.crlf_lines
      HTTP/1.1 101 Switching Protocols
      Upgrade: echo
      Connection: Upgrade

    HTTP
    assert_equal(expected, response)

    assert !done

    connection << 'foo'
    assert_equal 'foo', connection.readpartial(8192)

    connection << 'bar'
    assert_equal 'bar', connection.readpartial(8192)

    connection.close
    assert !done

    sleep 0.01
    assert done
  end

  def test_big_download
    chunk_size = 1000
    chunk_count = 1000
    chunk = '*' * chunk_size
    @server, connection = spin_server do |req|
      req.send_headers
      chunk_count.times do |i|
        req << chunk
        snooze
      end
      req.finish
      req.adapter.close
    end

    response = +''
    count = 0

    connection << "GET / HTTP/1.1\r\n\r\n"

    while (data = connection.read(chunk_size))
      response << data
      count += 1
      snooze
    end

    chunks = "#{chunk_size.to_s(16)}\n#{'*' * chunk_size}\n" * chunk_count
    expected = <<~HTTP.crlf_lines
      HTTP/1.1 200
      Transfer-Encoding: chunked

      #{chunks}0

    HTTP

    assert_equal expected, response
    assert count >= chunk_count
  end
end
