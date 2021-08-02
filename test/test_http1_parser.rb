# frozen_string_literal: true

require_relative 'helper'
require 'tipi_ext'
require_relative '../security/http1.rb'

class HTTP1ParserTest < MiniTest::Test
  Error = Tipi::HTTP1Parser::Error

  def setup
    super
    @i, @o = IO.pipe
    @parser = Tipi::HTTP1Parser.new(@i)
  end
  alias_method :reset_parser, :setup

  def test_request_line
    msg = "GET / HTTP/1.1\r\n\r\n"
    @o << msg
    headers = @parser.parse_headers

    assert_equal(
      {
        ':method' => 'get',
        ':path' => '/',
        ':protocol' => 'http/1.1',
        ':rx' => msg.bytesize
      },
      headers
    )
  end

  def test_request_line_whitespace
    msg = "GET       /               HTTP/1.1\r\n\r\n"
    @o << msg
    headers = @parser.parse_headers

    assert_equal(
      {
        ':method' => 'get',
        ':path' => '/',
        ':protocol' => 'http/1.1',
        ':rx' => msg.bytesize
      },
      headers
    )
  end

  def test_eof
    @o << "GET / HTTP/1.1"
    @o.close

    assert_nil @parser.parse_headers
  end

  def test_method_case
    @o << "GET / HTTP/1.1\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal 'get', headers[':method']

    reset_parser
    @o << "post / HTTP/1.1\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal 'post', headers[':method']

    reset_parser
    @o << "PoST / HTTP/1.1\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal 'post', headers[':method']
  end

  def test_bad_method
    @o << " / HTTP/1.1\r\n\r\n"
    @o.close

    assert_raises(Error) { @parser.parse_headers }
  
    max_length = Tipi::HTTP1_LIMITS[:max_method_length]

    reset_parser
    @o << "#{'a' * max_length} / HTTP/1.1\r\n\r\n"
    assert_equal 'a' * max_length, @parser.parse_headers[':method']

    reset_parser
    @o << "#{'a' * (max_length + 1)} / HTTP/1.1\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }
  end

  def test_path_characters
    @o << "GET /äBçDé¤23~{@€ HTTP/1.1\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal '/äBçDé¤23~{@€', headers[':path']

    reset_parser
    @o << "GET /%E5%86%86foo%20bar%25 HTTP/1.1\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal '/円foo bar%', headers[':path']
  end

  def test_bad_path
    @o << "GET HTTP/1.1\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }
  
    max_length = Tipi::HTTP1_LIMITS[:max_path_length]

    reset_parser
    @o << "get #{'a' * max_length} HTTP/1.1\r\n\r\n"
    assert_equal 'a' * max_length, @parser.parse_headers[':path']

    reset_parser
    @o << "get #{'a' * (max_length + 1)} HTTP/1.1\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }
  end

  def test_protocol
    @o << "GET / http/1\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal 'http/1', headers[':protocol']

    reset_parser
    @o << "GET / HTTP/1\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal 'http/1', headers[':protocol']

    reset_parser
    @o << "GET / HTTP/1.0\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal 'http/1.0', headers[':protocol']

    @o << "GET / HttP/1.1\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal 'http/1.1', headers[':protocol']
  end

    def test_bad_protocol
    @o << "GET / blah\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }

    reset_parser
    @o << "GET / http\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }

    reset_parser
    @o << "GET / http/2\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }

    reset_parser
    @o << "GET / http/1.\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }

    reset_parser
    @o << "GET / http/a.1\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }

    reset_parser
    @o << "GET / http/1.1.1\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }
  end

  def test_headers_eof
    @o << "GET / HTTP/1.1\r\na"
    @o.close
    
    assert_nil @parser.parse_headers

    reset_parser
    @o << "GET / HTTP/1.1\r\na:"
    @o.close
    
    assert_nil @parser.parse_headers

    reset_parser
    @o << "GET / HTTP/1.1\r\na:      "
    @o.close
    
    assert_nil @parser.parse_headers
  end

  def test_headers
    @o << "GET / HTTP/1.1\r\nFoo: Bar\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal [':method', ':path', ':protocol', 'foo', ':rx'], headers.keys
    assert_equal 'Bar', headers['foo']

    reset_parser
    @o << "GET / HTTP/1.1\r\nFOO:    baR\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal 'baR', headers['foo']

    reset_parser
    @o << "GET / HTTP/1.1\r\na: bbb\r\nc: ddd\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal 'bbb', headers['a']
    assert_equal 'ddd', headers['c']
  end

  def test_headers_multiple_values
    @o << "GET / HTTP/1.1\r\nFoo: Bar\r\nfoo: baz\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal ['Bar', 'baz'], headers['foo']
  end

  def test_bad_headers
    @o << "GET / http/1.1\r\n   a: b\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }

    reset_parser
    @o << "GET / http/1.1\r\na b\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }

    max_key_length = Tipi::HTTP1_LIMITS[:max_header_key_length]

    reset_parser
    @o << "GET / http/1.1\r\n#{'a' * max_key_length}: b\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal 'b', headers['a' * max_key_length]

    reset_parser
    @o << "GET / http/1.1\r\n#{'a' * (max_key_length + 1)}: b\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }

    max_value_length = Tipi::HTTP1_LIMITS[:max_header_value_length]

    reset_parser
    @o << "GET / http/1.1\r\nfoo: #{'a' * max_value_length}\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal 'a' * max_value_length, headers['foo']

    reset_parser
    @o << "GET / http/1.1\r\nfoo: #{'a' * (max_value_length + 1)}\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }

    max_header_count = Tipi::HTTP1_LIMITS[:max_header_count]

    reset_parser
    hdrs = (1..max_header_count).map { |i| "foo#{i}: bar\r\n" }.join
    @o << "GET / http/1.1\r\n#{hdrs}\r\n"
    headers = @parser.parse_headers
    assert_equal (max_header_count + 4), headers.size

    reset_parser
    hdrs = (1..(max_header_count + 1)).map { |i| "foo#{i}: bar\r\n" }.join
    @o << "GET / http/1.1\r\n#{hdrs}\r\n"
    assert_raises(Error) { @parser.parse_headers }
  end

  def test_request_without_cr
    msg = "GET /foo HTTP/1.1\nBar: baz\n\n"
    @o << msg
    headers = @parser.parse_headers
    assert_equal({
      ':method'   => 'get',
      ':path'     => '/foo',
      ':protocol' => 'http/1.1',
      'bar'       => 'baz',
      ':rx'       => msg.bytesize
    }, headers)
  end

  def test_read_body_with_content_length
    10.times do
      data = ' ' * rand(20..60000)
      msg = "POST /foo HTTP/1.1\r\nContent-Length: #{data.bytesize}\r\n\r\n#{data}"
      spin do
        @o << msg
      end
      headers = @parser.parse_headers
      assert_equal data.bytesize.to_s, headers['content-length']

      body = @parser.read_body
      assert_equal data, body
      assert_equal msg.bytesize, headers[':rx']
    end
  end

  def test_read_body_chunk_with_content_length
    data = 'abc' * (1 << 20)
    msg = "POST /foo HTTP/1.1\r\nContent-Length: #{data.bytesize}\r\n\r\n#{data}"
    spin do
      @o << msg
    end
    headers = @parser.parse_headers
    assert_equal data.bytesize.to_s, headers['content-length']

    buf = +''
    count = 0
    while (chunk = @parser.read_body_chunk(false))
      count += 1
      buf += chunk
    end
    # we're dealing with pipes, so chunks are limited to 64KB (???)
    assert_equal data.bytesize / (2**16), count
    assert_equal data, buf
    assert_equal msg.bytesize, headers[':rx']
  end

  def test_read_body_with_content_length_incomplete
    data = ' ' * rand(20..60000)
    spin do
      @o << "POST /foo HTTP/1.1\r\nContent-Length: #{data.bytesize + 1}\r\n\r\n#{data}"
      @o.close # !!! otherwise the parser will keep waiting
    end
    headers = @parser.parse_headers

    assert_raises(Tipi::HTTP1Parser::Error) { @parser.read_body }
  end

  def test_read_body_chunk_with_content_length_incomplete
    data = 'abc' * (1 << 20)
    spin do
      @o << "POST /foo HTTP/1.1\r\nContent-Length: #{data.bytesize + 1}\r\n\r\n#{data}"
      @o.close
    end
    headers = @parser.parse_headers

    expected_chunk_count = data.bytesize / (2**16)

    expected_chunk_count.times do
      chunk = @parser.read_body_chunk(false)
      assert chunk # not nil
    end

    assert_raises(Tipi::HTTP1Parser::Error) { @parser.read_body_chunk(false) }
  end

  def test_read_body_with_chunked_encoding
    chunks = []
    total_sent = 0
    spin do
      msg = "POST /foo HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
      @o << msg
      total_sent += msg.bytesize
      rand(8..16).times do |i|
        chunk = i.to_s * rand(40000..360000)
        msg = "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n"
        @o << msg
        chunks << chunk
        total_sent += msg.bytesize
      end
      msg = "0\r\n\r\n"
      @o << msg
      total_sent += msg.bytesize
    end 
    headers = @parser.parse_headers
    assert_equal 'chunked', headers['transfer-encoding']

    body = @parser.read_body
    assert_equal chunks.join, body
    assert_equal total_sent, headers[':rx']
  end

  def test_read_body_chunk_with_chunked_encoding
    chunks = []
    total_sent = 0
    spin do
      msg = "POST /foo HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
      @o << msg
      total_sent += msg.bytesize
      rand(8..16).times do |i|
        chunk = i.to_s * rand(40000..360000)
        msg = "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n"
        @o << msg
        total_sent += msg.bytesize
        chunks << chunk
      end
      msg = "0\r\n\r\n"
      @o << msg
      total_sent += msg.bytesize
    end 
    headers = @parser.parse_headers
    assert_equal 'chunked', headers['transfer-encoding']

    received = []
    while (chunk = @parser.read_body_chunk(false))
      received << chunk
    end
    assert_equal chunks, received
    assert_equal total_sent, headers[':rx']
  end

  def test_read_body_with_chunked_encoding_malformed
    spin do
      @o << "POST /foo HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
      chunk = ' '.to_s * rand(40000..360000)
      @o << "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n3"
      @o << "0\r\n\r\n"
      @o.close
    end
    headers = @parser.parse_headers
    assert_raises(Tipi::HTTP1Parser::Error) { @parser.read_body }

    reset_parser
    # missing last empty chunk
    spin do
      @o << "POST /foo HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
      chunk = ' '.to_s * rand(40000..360000)
      @o << "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n"
      @o.close
    end 
    headers = @parser.parse_headers
    assert_raises(Tipi::HTTP1Parser::Error) { @parser.read_body }

    reset_parser
    # bad chunk size
    spin do
      @o << "POST /foo HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
      chunk = ' '.to_s * rand(40000..360000)
      @o << "-#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n"
      @o.close
    end 
    headers = @parser.parse_headers
    assert_raises(Tipi::HTTP1Parser::Error) { @parser.read_body }
  end

  def test_read_body_chunk_with_chunked_encoding_malformed
    chunk = nil
    spin do
      @o << "POST /foo HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
      chunk = ' ' * rand(40000..360000)
      @o << "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n3"
      @o << "0\r\n\r\n"
      @o.close
    end
    headers = @parser.parse_headers
    read = @parser.read_body_chunk(false)
    assert_equal chunk, read
    assert_raises(Tipi::HTTP1Parser::Error) { @parser.read_body_chunk(false) }

    reset_parser
    Fiber.current.shutdown_all_children
    # missing last empty chunk
    chunk = nil
    spin do
      @o << "POST /foo HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
      chunk = ' '.to_s * rand(20..1600)
      @o << "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n"
      @o.close
    end
    headers = @parser.parse_headers
    read = @parser.read_body_chunk(false)
    assert_equal chunk, read
    assert_raises(Tipi::HTTP1Parser::Error) { @parser.read_body_chunk(false) }

    reset_parser
    Fiber.current.shutdown_all_children
    # bad chunk size
    spin do
      @o << "POST /foo HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
      chunk = ' '.to_s * rand(20..1600)
      @o << "-#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n"
      @o.close
    end 
    headers = @parser.parse_headers
    assert_raises(Tipi::HTTP1Parser::Error) { @parser.read_body_chunk(false) }

    reset_parser
    Fiber.current.shutdown_all_children
    # missing body
    @o << "POST /foo HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
    @o.close
    headers = @parser.parse_headers
    assert_raises(Tipi::HTTP1Parser::Error) { @parser.read_body_chunk(false) }
  ensure
    Fiber.current.shutdown_all_children
  end

  def test_complete?
    @o << "GET / HTTP/1.1\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal true, @parser.complete?

    reset_parser
    @o << "GET / HTTP/1.1\r\nContent-Length: 3\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal false, @parser.complete?
    @o << 'foo'
    body = @parser.read_body
    assert_equal 'foo', body
    assert_equal true, @parser.complete?

    reset_parser
    @o << "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal false, @parser.complete?
    @o << "3\r\nfoo\r\n"
    chunk = @parser.read_body_chunk(false)
    assert_equal 'foo', chunk
    assert_equal false, @parser.complete?
    @o << "0\r\n\r\n"
    chunk = @parser.read_body_chunk(false)
    assert_nil chunk
    assert_equal true, @parser.complete?
  end

  def test_parser_with_tcp_socket
    port = rand(1234..5678)
    server = TCPServer.new('127.0.0.1', port)
    server_fiber = spin do
      while (socket = server.accept)
        spin do
          parser = Tipi::HTTP1Parser.new(socket)
          headers = parser.parse_headers
          socket << headers.inspect
          socket.shutdown
          socket.close
        end
      end
    end

    snooze
    client = TCPSocket.new('127.0.0.1', port)
    msg = "get /foo HTTP/1.1\r\nCookie: abc=def\r\n\r\n"
    client << msg
    reply = client.read
    assert_equal({
      ':method' => 'get',
      ':path' => '/foo',
      ':protocol' => 'http/1.1',
      'cookie' => 'abc=def',
      ':rx' => msg.bytesize,
    }, eval(reply))
  ensure
    client.shutdown rescue nil
    client&.close
    server_fiber&.stop
    server_fiber&.await
    server&.close
  end
end
