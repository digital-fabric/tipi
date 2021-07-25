#include "ruby.h"
#include "http1_parser.h"

#define str_downcase(str) (rb_funcall((str), ID_downcase, 0))

const int MAX_METHOD_LENGTH = 16;
const int MAX_PATH_LENGTH = 1024;

ID ID_read;
ID ID_readpartial;
ID ID_downcase;

VALUE MAX_READ_LENGTH;
VALUE BUFFER_END;

VALUE KEY_METHOD;
VALUE KEY_PATH;
VALUE KEY_PROTOCOL;

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

VALUE Parser_initialize(VALUE self, VALUE io, VALUE buffer) {
  Parser_t *parser;
  GetParser(self, parser);

  parser->io = io;
  parser->buffer = buffer;
  parser->pos = 0;

  return self;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

struct parser_state {
  struct parser *parser;
  char *ptr;
  int len;
};

static inline int fill_buffer(struct parser_state *state) {
  int read_bytes = NUM2INT(
    rb_funcall(
      state->parser->io,
      ID_readpartial,
      3,
      state->parser->buffer,
      MAX_READ_LENGTH,
      BUFFER_END
    )
  );
  if (read_bytes == 0) return 0;
  
  state->ptr = RSTRING_PTR(state->parser->buffer);
  state->len = RSTRING_LEN(state->parser->buffer);
  return read_bytes;
}

#define FILL_BUFFER_OR_GOTO_EOF(state) { if (!fill_buffer(state)) goto eof; }

#define BUFFER_POS(state) (state->parser->pos)
#define BUFFER_LEN(state) (state->len)
#define BUFFER_CUR(state) (state->ptr[state->parser->pos])
#define BUFFER_AT(state, pos) (state->ptr[pos])
#define BUFFER_STR(state, pos, len) (rb_str_new(state->ptr + pos, len))

#define INC_BUFFER_POS(state) { \
  BUFFER_POS(state)++; \
  if (BUFFER_POS(state) == BUFFER_LEN(state)) FILL_BUFFER_OR_GOTO_EOF(state); \
}

#define INC_BUFFER_POS_UTF8(state) { \
  char c = BUFFER_CUR(state); \
  if (c & 0xF0) { \
    while (BUFFER_LEN(state) - BUFFER_POS(state) < 4) FILL_BUFFER_OR_GOTO_EOF(state); \
    BUFFER_POS(state) += 4; \
  } \
  else if (c & 0xE0) { \
    while (BUFFER_LEN(state) - BUFFER_POS(state) < 3) FILL_BUFFER_OR_GOTO_EOF(state); \
    BUFFER_POS(state) += 3; \
  } \
  else if (c & 0xC0) { \
    while (BUFFER_LEN(state) - BUFFER_POS(state) < 2) FILL_BUFFER_OR_GOTO_EOF(state); \
    BUFFER_POS(state) += 2; \
  } \
  else { \
    BUFFER_POS(state)++; \
    if (BUFFER_POS(state) == BUFFER_LEN(state)) FILL_BUFFER_OR_GOTO_EOF(state); \
  } \
}

#define INIT_PARSER_STATE(state) { \
  state->len = RSTRING_LEN(state->parser->buffer); \
  if (BUFFER_POS(state) == BUFFER_LEN(state)) \
    FILL_BUFFER_OR_GOTO_EOF(state) \
  else \
    state->ptr = RSTRING_PTR(state->parser->buffer); \
}

#define RAISE_BAD_REQUEST(msg) rb_raise(rb_eRuntimeError, msg)

// #define SET_HEADER_VALUE_FROM_BUFFER(state, headers, key, pos, len) { \
//   VALUE value = BUFFER_STR(state, pos, len));
//   rb_hash_aset(headers, key, value);
//   RB_GC_GUARD(value);
// }

// #define SET_HEADER_DOWNCASE_VALUE_FROM_BUFFER(state, headers, key, pos, len) { \
//   VALUE value = str_downcase(BUFFER_STR(state, pos, len)));
//   rb_hash_aset(headers, key, value);
//   RB_GC_GUARD(value);
// }

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

static inline int parse_method(struct parser_state *state, VALUE headers) {
  int pos = BUFFER_POS(state);
  int len = 0;

loop:
  switch (BUFFER_CUR(state)) {
    case ' ':
      if (len < 1 || len > MAX_METHOD_LENGTH) goto bad_request;
      INC_BUFFER_POS(state);
      goto done;
    case '\r':
    case '\n':
      goto bad_request;
    default:
      len++;
      if (len >= MAX_METHOD_LENGTH) goto bad_request;
      INC_BUFFER_POS_UTF8(state);
      goto loop;
  }
done:
  // SET_HEADER_DOWNCASE_VALUE_FROM_BUFFER(state, headers, KEY_METHOD, pos, len);
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
loop:
  switch (BUFFER_CUR(state)) {
    case ' ':
      if (len < 1 || len > MAX_PATH_LENGTH) goto bad_request;
      INC_BUFFER_POS(state);
      goto done;
    case '\r':
    case '\n':
      goto bad_request;
    default:
      len++;
      if (len >= MAX_PATH_LENGTH) goto bad_request;
      INC_BUFFER_POS_UTF8(state);
      goto loop;
  }
done:
  // SET_HEADER_VALUE_FROM_BUFFER(state, headers, KEY_PATH, pos, len);
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
loop:
  switch (BUFFER_CUR(state)) {
    case '\r':
      INC_BUFFER_POS(state);
      goto eol;
    case '\n':
      INC_BUFFER_POS(state);
      goto done;
    case '.':
    case '1':
      len++;
      if (len >= 8) goto bad_request;
      INC_BUFFER_POS(state);
      goto loop;
    default:
      goto bad_request;
  }
eol:
  if (BUFFER_CUR(state) != '\n') goto bad_request;
  INC_BUFFER_POS(state);
done:
  if (len < 6 || len > 8) goto bad_request;
  // SET_HEADER_DOWNCASE_VALUE_FROM_BUFFER(state, headers, KEY_PROTOCOL, pos, len);
  return 1;
bad_request:
  RAISE_BAD_REQUEST("Invalid protocol");
eof:
  return 0;
}

int parse_request_line(struct parser_state *state, VALUE headers) {
  INIT_PARSER_STATE(state);

  if (!parse_method(state, headers)) goto eof;
  if (!parse_path(state, headers)) goto eof;
  if (!parse_protocol(state, headers)) goto eof;

  return 1;
eof:
  return 0;
}

VALUE Parser_parse_headers(VALUE self) {
  struct parser_state state;
  GetParser(self, state.parser);
  VALUE headers = rb_hash_new();

  if (!parse_request_line(&state, headers)) goto eof;

// state_key:
//   int key_pos = BUFFER_POS(state);
//   int key_len = 0;
// state_key_loop:
//   switch (BUFFER_CUR(state)) {
//     case ':':
//       if (key_len < 1 || key_len > MAX_HEADER_KEY_LENGTH)
//         goto state_malformed_request;
//       INC_BUFFER_POS(state);
//       goto state_value;
//     case '\r':
//       if (BUFFER_POS(state) > key_pos) goto state_malformed_request;

//       INC_BUFFER_POS(state);
//       goto state_empty_header_eol;
//     case '\n':
//       if (BUFFER_POS(state) > key_pos) goto state_malformed_request;

//       INC_BUFFER_POS(state);
//       goto state_headers_complete;
//     default:
//       key_len++;
//       if (key_len >= MAX_HEADER_KEY_LENGTH) goto state_malformed_request;
//       INC_BUFFER_POS_UTF8(state);
//       goto state_key_loop;
//   }
// state_empty_header_eol:
//   if (BUFFER_CUR(state) != '\n') goto state_malformed_request;
//   INC_BUFFER_POS(state);
//   goto state_headers_complete;
// state_value:
//   while (BUFFER_CUR(state) == ' ') INC_BUFFER_POS(state);
//   int value_pos = pos;
//   int value_len = 0;
// state_value_loop:
//   switch (BUFFER_CUR(state)) {
//     case '\r':
//       INC_BUFFER_POS(state);
//       goto state_value_eol;
//     case '\n':
//       goto state_header_line_complete;
//     default:
//       value_len++;
//       if (value_len >= MAX_HEADER_VALUE_LENGTH) goto state_malformed_request;
//       INC_BUFFER_POS_UTF8(state);
//       goto state_value_loop;

//   }
// state_value_eol:
//   if (BUFFER_CUR(state) != '\n') goto state_malformed_request;
// state_header_line_complete:
//   if (value_len < 1 || value_len > MAX_HEADER_VALUE_LENGTH) goto state_malformed_request;
//   INC_BUFFER_POS(state);

//   VALUE key = str_downcase(BUFFER_STR(state, key_pos, key_len));
//   VALUE value = BUFFER_STR(state, value_pos, value_len);

//   VALUE existing = rb_hash_get(headers, key);
//   if (existing != Qnil) {
//     if (RTYPE(existing) != R_ARRAY) {
//       existing = rb_ary_new3(2, existing, value);
//       rb_hash_set(headers, key, existing);
//     }
//     else
//       rb_ary_push(existing, value);
//   }
//   else
//     rb_hash_set(headers, key, value);

//   RB_GC_GUARD(key);
//   RB_GC_GUARD(value);
//   goto state_key;
// state_headers_complete:
  RB_GC_GUARD(headers);
  return headers;
// state_malformed_request:
//   return rb_raise(cError, "Malformed request");
eof:
  return Qnil;
}

void Init_Polyphony() {
  VALUE mTipi;
  VALUE cHTTP1Parser;

  mTipi = rb_define_module("Tipi");
  cHTTP1Parser = rb_define_class_under(mTipi, "HTT1Parser", rb_cObject);
  rb_define_alloc_func(cHTTP1Parser, Parser_allocate);


  // backend methods
  rb_define_method(cHTTP1Parser, "initialize", Parser_initialize, 2);
  // rb_define_method(cHTTP1Parser, "parse_headers", Parser_parse_headers, 0);

  ID_read         = rb_intern("read");
  ID_readpartial  = rb_intern("readpartial");
  ID_downcase     = rb_intern("downcase");

  MAX_READ_LENGTH = INT2NUM(4096);
  BUFFER_END = INT2NUM(-1);

  KEY_METHOD    = rb_str_new_literal(":method");
  KEY_PATH      = rb_str_new_literal(":path");
  KEY_PROTOCOL  = rb_str_new_literal(":protocol");
}
