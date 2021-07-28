#include "ruby.h"
#include "http1_parser.h"

// Securit-related limits are defined in security/http1.rb and injected as
// defines in extconf.rb

#define INITIAL_BUFFER_SIZE     4096
#define BUFFER_TRIM_MIN_LEN     4096
#define BUFFER_TRIM_MIN_POS     2048
#define MAX_HEADERS_READ_LENGTH 4096
#define MAX_BODY_READ_LENGTH    (1 << 20)

ID ID_backend_read;
ID ID_downcase;
ID ID_eq;
ID ID_read;
ID ID_readpartial;
ID ID_to_i;

VALUE cError;

VALUE NUM_max_headers_read_length;
VALUE NUM_buffer_end;

VALUE STR_pseudo_method;
VALUE STR_pseudo_path;
VALUE STR_pseudo_protocol;
VALUE STR_pseudo_request_body_left;

VALUE STR_chunked;
VALUE STR_content_length;
VALUE STR_transfer_encoding;

typedef struct parser {
  VALUE io;
  VALUE buffer;
  int pos;
} Parser_t;

VALUE cParser = Qnil;

static void Parser_mark(void *ptr) {
  Parser_t *parser = ptr;
  rb_gc_mark(parser->io);
  rb_gc_mark(parser->buffer);
}

static void Parser_free(void *ptr) {
  Parser_t *parser = ptr;
  xfree(ptr);
}

static size_t Parser_size(const void *ptr) {
  return sizeof(Parser_t);
}

static const rb_data_type_t Parser_type = {
  "Parser",
  {Parser_mark, Parser_free, Parser_size,},
  0, 0, 0
};

static VALUE Parser_allocate(VALUE klass) {
  Parser_t *parser;

  parser = ALLOC(Parser_t);
  return TypedData_Wrap_Struct(klass, &Parser_type, parser);
}

#define GetParser(obj, parser) \
  TypedData_Get_Struct((obj), Parser_t, &Parser_type, (parser))

VALUE Parser_initialize(VALUE self, VALUE io) {
  Parser_t *parser;
  GetParser(self, parser);

  parser->io = io;
  parser->buffer = rb_str_new_literal("");
  parser->pos = 0;

  // pre-allocate the buffer
  rb_str_modify_expand(parser->buffer, INITIAL_BUFFER_SIZE);

  return self;
}

////////////////////////////////////////////////////////////////////////////////

#define str_downcase(str) (rb_funcall((str), ID_downcase, 0))

#define READ_CONCAT(io, buffer, len) \
  rb_funcall(io, ID_readpartial, 4, len, buffer, NUM_buffer_end, Qfalse)

#define FILL_BUFFER_OR_GOTO_EOF(state) { if (!fill_buffer(state)) goto eof; }

#define BUFFER_POS(state) ((state)->parser->pos)
#define BUFFER_LEN(state) ((state)->len)
#define BUFFER_CUR(state) ((state)->ptr[(state)->parser->pos])
#define BUFFER_AT(state, pos) ((state)->ptr[pos])
#define BUFFER_STR(state, pos, len) (rb_utf8_str_new((state)->ptr + pos, len))

#define INC_BUFFER_POS(state) { \
  BUFFER_POS(state)++; \
  if (BUFFER_POS(state) == BUFFER_LEN(state)) FILL_BUFFER_OR_GOTO_EOF(state); \
}

#define INC_BUFFER_POS_NO_READ(state) BUFFER_POS(state)++;

#define INC_BUFFER_POS_UTF8(state, len) { \
  unsigned char c = BUFFER_CUR(state); \
  if ((c & 0xf0) == 0xf0) { \
    while (BUFFER_LEN(state) - BUFFER_POS(state) < 4) FILL_BUFFER_OR_GOTO_EOF(state); \
    BUFFER_POS(state) += 4; \
    len += 4; \
  } \
  else if ((c & 0xe0) == 0xe0) { \
    while (BUFFER_LEN(state) - BUFFER_POS(state) < 3) FILL_BUFFER_OR_GOTO_EOF(state); \
    BUFFER_POS(state) += 3; \
    len += 3; \
  } \
  else if ((c & 0xc0) == 0xc0) { \
    while (BUFFER_LEN(state) - BUFFER_POS(state) < 2) FILL_BUFFER_OR_GOTO_EOF(state); \
    BUFFER_POS(state) += 2; \
    len += 2; \
  } \
  else { \
    BUFFER_POS(state)++; \
    len ++; \
    if (BUFFER_POS(state) == BUFFER_LEN(state)) FILL_BUFFER_OR_GOTO_EOF(state); \
  } \
}

#define INIT_PARSER_STATE(state) { \
  (state)->len = RSTRING_LEN((state)->parser->buffer); \
  if (BUFFER_POS(state) == BUFFER_LEN(state)) \
    FILL_BUFFER_OR_GOTO_EOF(state) \
  else \
    (state)->ptr = RSTRING_PTR((state)->parser->buffer); \
}

#define RAISE_BAD_REQUEST(msg) rb_raise(cError, msg)

#define SET_HEADER_VALUE_FROM_BUFFER(state, headers, key, pos, len) { \
  VALUE value = BUFFER_STR(state, pos, len); \
  rb_hash_aset(headers, key, value); \
  RB_GC_GUARD(value); \
}

#define SET_HEADER_DOWNCASE_VALUE_FROM_BUFFER(state, headers, key, pos, len) { \
  VALUE value = str_downcase(BUFFER_STR(state, pos, len)); \
  rb_hash_aset(headers, key, value); \
  RB_GC_GUARD(value); \
}

#define CONSUME_CRLF(state) { \
  INC_BUFFER_POS(state); \
  if (BUFFER_CUR(state) != '\n') goto bad_request; \
  INC_BUFFER_POS(state); \
}

#define CONSUME_CRLF_NO_READ(state) { \
  INC_BUFFER_POS(state); \
  if (BUFFER_CUR(state) != '\n') goto bad_request; \
  INC_BUFFER_POS_NO_READ(state); \
}

#define GLOBAL_STR(v, s) v = rb_str_new_literal(s); rb_global_variable(&v)

struct parser_state {
  struct parser *parser;
  char *ptr;
  int len;
};

////////////////////////////////////////////////////////////////////////////////

static inline int fill_buffer(struct parser_state *state) {
  READ_CONCAT(state->parser->io, state->parser->buffer, NUM_max_headers_read_length);
  int len = RSTRING_LEN(state->parser->buffer);
  int read_bytes = len - state->len;
  if (!read_bytes) return 0;
  
  state->ptr = RSTRING_PTR(state->parser->buffer);
  state->len = len;
  return read_bytes;
}

static inline void buffer_trim(struct parser_state *state) {
  int len = RSTRING_LEN(state->parser->buffer);
  int pos = state->parser->pos;
  int left = len - pos;

  // The buffer is trimmed only if length and position thresholds are passed,
  // *and* position is past the halfway point. 
  if (len < BUFFER_TRIM_MIN_LEN || 
      pos < BUFFER_TRIM_MIN_POS ||
      left >= pos) return;

  if (left > 0) {
    char *ptr = RSTRING_PTR(state->parser->buffer);
    memcpy(ptr, ptr + pos, left);
  }
  rb_str_set_len(state->parser->buffer, left);
  state->parser->pos = 0;
}

static inline void str_append_from_buffer(VALUE str, char *ptr, int len) {
  int str_len = RSTRING_LEN(str);
  rb_str_modify_expand(str, len);
  memcpy(RSTRING_PTR(str) + str_len, ptr, len);
  rb_str_set_len(str, str_len + len);
}

////////////////////////////////////////////////////////////////////////////////

static inline int parse_method(struct parser_state *state, VALUE headers) {
  int pos = BUFFER_POS(state);
  int len = 0;

  while (1) {
    switch (BUFFER_CUR(state)) {
      case ' ':
        if (len < 1 || len > MAX_METHOD_LENGTH) goto bad_request;
        INC_BUFFER_POS(state);
        goto done;
      case '\r':
      case '\n':
        goto bad_request;
      default:
        INC_BUFFER_POS_UTF8(state, len);
        if (len > MAX_METHOD_LENGTH) goto bad_request;
    }
  }
done:
  SET_HEADER_DOWNCASE_VALUE_FROM_BUFFER(state, headers, STR_pseudo_method, pos, len);
  return 1;
bad_request:
  RAISE_BAD_REQUEST("Invalid method");
eof:
  return 0;
}

static int parse_path(struct parser_state *state, VALUE headers) {
  while (BUFFER_CUR(state) == ' ') INC_BUFFER_POS(state);
  int pos = BUFFER_POS(state);
  int len = 0;
  while (1) {
    switch (BUFFER_CUR(state)) {
      case ' ':
        if (len < 1 || len > MAX_PATH_LENGTH) goto bad_request;
        INC_BUFFER_POS(state);
        goto done;
      case '\r':
      case '\n':
        goto bad_request;
      default:
        INC_BUFFER_POS_UTF8(state, len);
        if (len > MAX_PATH_LENGTH) goto bad_request;
    }
  }
done:
  SET_HEADER_VALUE_FROM_BUFFER(state, headers, STR_pseudo_path, pos, len);
  return 1;
bad_request:
  RAISE_BAD_REQUEST("Invalid path");
eof:
  return 0;
}

// case-insensitive compare
#define CMP_CI(state, down, up) ((BUFFER_CUR(state) == down) || (BUFFER_CUR(state) == up))

static int parse_protocol(struct parser_state *state, VALUE headers) {
  while (BUFFER_CUR(state) == ' ') INC_BUFFER_POS(state);
  int pos = BUFFER_POS(state);
  int len = 0;

  if (CMP_CI(state, 'H', 'h')) INC_BUFFER_POS(state) else goto bad_request;
  if (CMP_CI(state, 'T', 't')) INC_BUFFER_POS(state) else goto bad_request;
  if (CMP_CI(state, 'T', 't')) INC_BUFFER_POS(state) else goto bad_request;
  if (CMP_CI(state, 'P', 'p')) INC_BUFFER_POS(state) else goto bad_request;
  if (BUFFER_CUR(state) == '/') INC_BUFFER_POS(state) else goto bad_request;
  if (BUFFER_CUR(state) == '1') INC_BUFFER_POS(state) else goto bad_request;
  len = 6;
  while (1) {
    switch (BUFFER_CUR(state)) {
      case '\r':
        CONSUME_CRLF(state);
        goto done;
      case '\n':
        INC_BUFFER_POS(state);
        goto done;
      case '.':
        INC_BUFFER_POS(state);
        if (BUFFER_CUR(state) != '1') goto bad_request;
        INC_BUFFER_POS(state);
        len += 2;
        continue;
      default:
        goto bad_request;
    }
  }
done:
  if (len < 6 || len > 8) goto bad_request;
  SET_HEADER_DOWNCASE_VALUE_FROM_BUFFER(state, headers, STR_pseudo_protocol, pos, len);
  return 1;
bad_request:
  RAISE_BAD_REQUEST("Invalid protocol");
eof:
  return 0;
}

int parse_request_line(struct parser_state *state, VALUE headers) {
  if (!parse_method(state, headers)) goto eof;
  if (!parse_path(state, headers)) goto eof;
  if (!parse_protocol(state, headers)) goto eof;

  return 1;
eof:
  return 0;
}

static inline int parse_header_key(struct parser_state *state, VALUE *key) {
  int pos = BUFFER_POS(state);
  int len = 0;

  while (1) {
    switch (BUFFER_CUR(state)) {
      case ' ':
        goto bad_request;
      case ':':
        if (len < 1 || len > MAX_HEADER_KEY_LENGTH)
          goto bad_request;
        INC_BUFFER_POS(state);
        goto done;
      case '\r':
        if (BUFFER_POS(state) > pos) goto bad_request;
        CONSUME_CRLF_NO_READ(state);
        goto done;
      case '\n':
        if (BUFFER_POS(state) > pos) goto bad_request;

        INC_BUFFER_POS_NO_READ(state);
        goto done;
      default:
        INC_BUFFER_POS_UTF8(state, len);
        if (len > MAX_HEADER_KEY_LENGTH) goto bad_request;
    }
  }
done:
  if (len == 0) return -1;
  (*key) = str_downcase(BUFFER_STR(state, pos, len));
  return 1;
bad_request:
  RAISE_BAD_REQUEST("Invalid header key");
eof:
  return 0;
}

static inline int parse_header_value(struct parser_state *state, VALUE *value) {
  while (BUFFER_CUR(state) == ' ') INC_BUFFER_POS(state);

  int pos = BUFFER_POS(state);
  int len = 0;

  while (1) {
    switch (BUFFER_CUR(state)) {
      case '\r':
        CONSUME_CRLF(state);
        goto done;
      case '\n':
        goto done;
      default:
        INC_BUFFER_POS_UTF8(state, len);
        if (len > MAX_HEADER_VALUE_LENGTH) goto bad_request;
    }
  }
done:
  if (len < 1 || len > MAX_HEADER_VALUE_LENGTH) goto bad_request;
  (*value) = BUFFER_STR(state, pos, len);
  return 1;
bad_request:
  RAISE_BAD_REQUEST("Invalid header value");
eof:
  return 0;
}

static inline int parse_header(struct parser_state *state, VALUE headers) {
  VALUE key, value;

  switch (parse_header_key(state, &key)) {
    case -1: return -1;
    case 0: goto eof;
  }

  if (!parse_header_value(state, &value)) goto eof;

  VALUE existing = rb_hash_aref(headers, key);
  if (existing != Qnil) {
    if (TYPE(existing) != T_ARRAY) {
      existing = rb_ary_new3(2, existing, value);
      rb_hash_aset(headers, key, existing);
    }
    else
      rb_ary_push(existing, value);
  }
  else
    rb_hash_aset(headers, key, value);

  RB_GC_GUARD(existing);
  RB_GC_GUARD(key);
  RB_GC_GUARD(value);
  return 1;
eof:
  return 0;
}

VALUE Parser_parse_headers(VALUE self) {
  struct parser_state state;
  GetParser(self, state.parser);
  VALUE headers = rb_hash_new();

  buffer_trim(&state);
  INIT_PARSER_STATE(&state);

  if (!parse_request_line(&state, headers)) goto eof;

  int header_count = 0;
  while (1) {
    if (header_count > MAX_HEADER_COUNT) RAISE_BAD_REQUEST("Too many headers");
    switch (parse_header(&state, headers)) {
      case -1: goto done; // empty header => end of headers
      case 0: goto eof;
    }
    header_count++;
  }
done:
  RB_GC_GUARD(headers);
  return headers;
eof:
  return Qnil;
}

////////////////////////////////////////////////////////////////////////////////

static inline int str_to_int(VALUE value, const char *error_msg) {
  char *ptr = RSTRING_PTR(value);
  int len = RSTRING_LEN(value);
  int int_value = 0;

  while (len) {
    char c = *ptr;
    if ((c >= '0') && (c <= '9'))
      int_value = int_value * 10 + (c - '0');
    else
      RAISE_BAD_REQUEST(error_msg);
    len--;
    ptr++;
  }

  return int_value;
}

static inline int parse_content_length(VALUE value) {
  return str_to_int(value, "Invalid content length");
}

VALUE read_body_with_content_length(VALUE self, VALUE headers, int content_length, int read_entire_body) {
  if (content_length < 0) return Qnil;

  Parser_t *parser;
  GetParser(self, parser);

  VALUE body;

  VALUE left_header = rb_hash_aref(headers, STR_pseudo_request_body_left);

  int len = RSTRING_LEN(parser->buffer);
  int pos = parser->pos;
  int left;

  if (left_header != Qnil)
    left = NUM2INT(left_header);
  else {
    left = content_length;
    rb_hash_aset(headers, STR_pseudo_request_body_left, INT2NUM(left));
  }

  if (!left) return Qnil;

  if (pos < len) {
    int available = len - pos;
    if (available > left) available = left;
    body = rb_str_new(RSTRING_PTR(parser->buffer) + pos, available);
    parser->pos += available;
    left -= available;
    len = available;
  }
  else {
    body = Qnil;
    len = 0;
  }
  
  while (left) {
    int maxlen = left <= MAX_BODY_READ_LENGTH ? left : MAX_BODY_READ_LENGTH;
    VALUE tmp_buf = rb_funcall(
      parser->io, ID_readpartial, 4, INT2NUM(maxlen), Qnil, INT2NUM(0), Qfalse
    );
    if (tmp_buf == Qnil) goto eof;

    if (body != Qnil)
      rb_str_append(body, tmp_buf);
    else
      body = tmp_buf;
    left -= RSTRING_LEN(tmp_buf);
    RB_GC_GUARD(tmp_buf);
    if (!read_entire_body) {
      rb_hash_aset(headers, STR_pseudo_request_body_left, INT2NUM(left));
      goto done;
    }
  }
  rb_hash_aset(headers, STR_pseudo_request_body_left, INT2NUM(0));
done:
  RB_GC_GUARD(body);
  return body;
eof:
  RAISE_BAD_REQUEST("Incomplete body");
}

int chunked_encoding_p(VALUE transfer_encoding) {
  if (transfer_encoding == Qnil) return 0;
  return rb_funcall(str_downcase(transfer_encoding), ID_eq, 1, STR_chunked) == Qtrue;
}

int parse_chunk_size(struct parser_state *state, int *chunk_size) {
  int len = 0;
  int value = 0;

  while (1) {
    char c = BUFFER_CUR(state);
    if ((c >= '0') && (c <= '9'))       value = (value << 4) + (c - '0');
    else if ((c >= 'a') && (c <= 'f'))  value = (value << 4) + (c - 'a' + 10);
    else if ((c >= 'A') && (c <= 'F'))  value = (value << 4) + (c - 'A' + 10);
    else switch (c) {
      case '\r':
        CONSUME_CRLF_NO_READ(state);
        goto done;
      case '\n':
        INC_BUFFER_POS_NO_READ(state);
        goto done;
      default:
        goto bad_request;
    }
    INC_BUFFER_POS(state);
    len++;
    if (len >= MAX_CHUNKED_ENCODING_CHUNK_SIZE_LENGTH) goto bad_request;
  }
done:
  if (len == 0) goto bad_request;
  (*chunk_size) = value;
  return 1;
bad_request:
  RAISE_BAD_REQUEST("Invalid chunk size");
eof:
  return 0;
}

int read_body_chunk_with_chunked_encoding(struct parser_state *state, VALUE *body, int chunk_size) {
  int len = RSTRING_LEN(state->parser->buffer);
  int pos = state->parser->pos;
  int left = chunk_size;

  if (pos < len) {
    int available = len - pos;
    if (available > left) available = left;
    if (*body != Qnil)
      str_append_from_buffer(*body, RSTRING_PTR(state->parser->buffer) + pos, available);
    else
      *body = rb_str_new(RSTRING_PTR(state->parser->buffer) + pos, available);
    state->parser->pos += available;
    left -= available;
  }

  while (left) {
    int maxlen = left <= MAX_BODY_READ_LENGTH ? left : MAX_BODY_READ_LENGTH;

    VALUE tmp_buf = rb_funcall(
      state->parser->io, ID_readpartial, 4, INT2NUM(maxlen), Qnil, INT2NUM(0), Qfalse
    );
    if (tmp_buf == Qnil) RAISE_BAD_REQUEST("Incomplete request body");
    
    if (*body != Qnil)
      rb_str_append(*body, tmp_buf);
    else
      *body = tmp_buf;
    int read_bytes = RSTRING_LEN(tmp_buf);
    RB_GC_GUARD(tmp_buf);

    if (!read_bytes) RAISE_BAD_REQUEST("Incomplete request body");
    left -= read_bytes;
  }
  return 1;
eof:
  return 0;
}

static inline int parse_chunk_postfix(struct parser_state *state) {
  if (BUFFER_POS(state) == BUFFER_LEN(state)) FILL_BUFFER_OR_GOTO_EOF(state);
  switch (BUFFER_CUR(state)) {
    case '\r':
      CONSUME_CRLF_NO_READ(state);
      goto done;
    case '\n':
      INC_BUFFER_POS_NO_READ(state);
      goto done;
    default:
      goto bad_request;
  }
done:
  return 1;
bad_request:
  RAISE_BAD_REQUEST("Invalid protocol");
eof:
  return 0;
}

VALUE read_body_with_chunked_encoding(VALUE self, VALUE headers, int read_entire_body) {
  struct parser_state state;
  GetParser(self, state.parser);

  buffer_trim(&state);
  INIT_PARSER_STATE(&state);

  VALUE body = Qnil;

  while (1) {
    int chunk_size = 0;
    if (!parse_chunk_size(&state, &chunk_size)) goto bad_request;
    
    if (chunk_size) {
      if (!read_body_chunk_with_chunked_encoding(&state, &body, chunk_size)) goto bad_request;
    }

    if (!parse_chunk_postfix(&state)) goto bad_request;
    if (!chunk_size || !read_entire_body) goto done;
  }
bad_request:
  RAISE_BAD_REQUEST("Malformed request body");
eof:
  RAISE_BAD_REQUEST("Incomplete request body");
done:
  RB_GC_GUARD(body);
  return body;
}

static inline VALUE read_body(VALUE self, VALUE headers, int read_entire_body) {
  VALUE content_length = rb_hash_aref(headers, STR_content_length);
  if (content_length != Qnil) {
    int content_length_int = parse_content_length(content_length);
    return read_body_with_content_length(
      self, headers, content_length_int, read_entire_body
    );
  }

  VALUE transfer_encoding = rb_hash_aref(headers, STR_transfer_encoding);
  if (chunked_encoding_p(transfer_encoding))
    return read_body_with_chunked_encoding(self, headers, read_entire_body);

  return Qnil;
}

VALUE Parser_read_body(VALUE self, VALUE headers) {
  return read_body(self, headers, 1);
}

VALUE Parser_read_body_chunk(VALUE self, VALUE headers) {
  return read_body(self, headers, 0);
}

void Init_HTTP1_Parser() {
  VALUE mTipi;
  VALUE cHTTP1Parser;

  mTipi = rb_define_module("Tipi");
  cHTTP1Parser = rb_define_class_under(mTipi, "HTTP1Parser", rb_cObject);
  rb_define_alloc_func(cHTTP1Parser, Parser_allocate);

  cError = rb_define_class_under(cHTTP1Parser, "Error", rb_eRuntimeError);

  // backend methods
  rb_define_method(cHTTP1Parser, "initialize", Parser_initialize, 1);
  rb_define_method(cHTTP1Parser, "parse_headers", Parser_parse_headers, 0);
  rb_define_method(cHTTP1Parser, "read_body", Parser_read_body, 1);
  rb_define_method(cHTTP1Parser, "read_body_chunk", Parser_read_body_chunk, 1);

  ID_backend_read = rb_intern("backend_read");
  ID_downcase     = rb_intern("downcase");
  ID_eq           = rb_intern("==");
  ID_read         = rb_intern("read");
  ID_readpartial  = rb_intern("readpartial");
  ID_to_i         = rb_intern("to_i");

  NUM_max_headers_read_length = INT2NUM(MAX_HEADERS_READ_LENGTH);
  NUM_buffer_end = INT2NUM(-1);

  GLOBAL_STR(STR_pseudo_method,       ":method");
  GLOBAL_STR(STR_pseudo_path,         ":path");
  GLOBAL_STR(STR_pseudo_protocol,     ":protocol");
  GLOBAL_STR(STR_pseudo_request_body_left,   ":request_body_left");

  GLOBAL_STR(STR_chunked,             "chunked");
  GLOBAL_STR(STR_content_length,      "content-length");
  GLOBAL_STR(STR_transfer_encoding,   "transfer-encoding");
}
