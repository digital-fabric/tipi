#include "http1_parser.h"


ID ID_read;
ID ID_readpartial;


void Init_Polyphony() {
  VALUE mTipi;
  VALUE cHTTP1Parser;

  mTipi = rb_define_module("Tipi");
  cHTTP1Parser = rb_define_class_under(mTipi, "HTT1Parser", rb_cObject);
  rb_define_alloc_func(cHTTP1Parser, Parser_allocate);


  // backend methods
  rb_define_singleton_method(cHTTP1Parser, "parse_headers", Parser_parse_headers, 0);

  ID_read         = rb_intern("read");
  ID_readpartial  = rb_intern("readpartial");
}