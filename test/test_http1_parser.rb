# frozen_string_literal: true

require_relative 'helper'
require 'tipi_ext'
require_relative '../security/http1.rb'

class HTTP1ParserTest < MiniTest::Test
  Error = Tipi::HTTP1Parser::Error

  def setup
    @i, @o = IO.pipe
    @parser = Tipi::HTTP1Parser.new(@i)
  end
  alias_method :reset_parser, :setup

  def test_request_line
    @o << "GET / HTTP/1.1\r\n\r\n"
    headers = @parser.parse_headers

    assert_equal(
      { ':method' => 'get', ':path' => '/', ':protocol' => 'http/1.1' },
      headers
    )
  end

  def test_request_line_whitespace
    @o << "GET       /               HTTP/1.1\r\n\r\n"
    headers = @parser.parse_headers

    assert_equal(
      { ':method' => 'get', ':path' => '/', ':protocol' => 'http/1.1' },
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
    @o << "GET /äBçDé¤23~{@€ HTTP/1.1\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal '/äBçDé¤23~{@€', headers[':path']
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
    assert_equal [':method', ':path', ':protocol', 'foo'], headers.keys
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
    assert_equal (max_header_count + 3), headers.size

    reset_parser
    hdrs = (1..(max_header_count + 1)).map { |i| "foo#{i}: bar\r\n" }.join
    @o << "GET / http/1.1\r\n#{hdrs}\r\n"
    assert_raises(Error) { @parser.parse_headers }
  end
end
