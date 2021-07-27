# frozen_string_literal: true

require_relative 'helper'
require 'tipi_ext'

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
  
    # method limit is 16 bytes
    reset_parser
    @o << "#{'a' * 16} / HTTP/1.1\r\n\r\n"
    assert_equal 'a' * 16, @parser.parse_headers[':method']

    reset_parser
    @o << "#{'a' * 17} / HTTP/1.1\r\n\r\n"
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
  
    # path limit is 4096 bytes
    reset_parser
    @o << "get #{'a' * 4096} HTTP/1.1\r\n\r\n"
    assert_equal 'a' * 4096, @parser.parse_headers[':path']

    reset_parser
    @o << "get #{'a' * 4097} HTTP/1.1\r\n\r\n"
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

    reset_parser
    @o << "GET / http/1.1\r\n#{'a' * 128}: b\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal 'b', headers['a' * 128]

    reset_parser
    @o << "GET / http/1.1\r\n#{'a' * 129}: b\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }

    reset_parser
    @o << "GET / http/1.1\r\nfoo: #{'a' * 2048}\r\n\r\n"
    headers = @parser.parse_headers
    assert_equal 'a' * 2048, headers['foo']

    reset_parser
    @o << "GET / http/1.1\r\nfoo: #{'a' * 2049}\r\n\r\n"
    assert_raises(Error) { @parser.parse_headers }

    reset_parser
    hdrs = (1..256).map { |i| "foo#{i}: bar\r\n" }.join
    @o << "GET / http/1.1\r\n#{hdrs}\r\n"
    headers = @parser.parse_headers
    assert_equal 259, headers.size

    reset_parser
    hdrs = (1..257).map { |i| "foo#{i}: bar\r\n" }.join
    @o << "GET / http/1.1\r\n#{hdrs}\r\n"
    assert_raises(Error) { @parser.parse_headers }
  end
end
