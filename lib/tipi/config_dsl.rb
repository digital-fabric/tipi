# frozen_string_literal: true

module Tipi
  module Configuration
    class Interpreter
      # make_blank_slate
      
      def initialize(assembler)
        @assembler = assembler
      end
      
      def gzip_response
        @assembler.emit 'req = Tipi::GZip.wrap(req)'
      end
      
      def log(out)
        @assembler.wrap_current_frame 'logger.log_request(req) do |req|'
      end
        
      def error(&block)
        assembler.emit_exception_handler &block
      end
        
      def match(pattern, &block)
        @assembler.emit_conditional "if req.path =~ #{pattern.inspect}", &block
      end
    end
      
    class Assembler
      def self.from_source(code)
        new.from_source code
      end

      def from_source(code)
        @stack = [new_frame]
        @app_procs = {}
        @interpreter = Interpreter.new self
        @interpreter.instance_eval code
        
        loop do
          frame = @stack.pop
          return assemble_app_proc(frame).join("\n") if @stack.empty?

          @stack.last[:body] << assemble_frame(frame)
        end
      end

      def new_frame
        {
          prelude: [],
          body: []
        }
      end
        
      def add_frame(&block)
        @stack.push new_frame
        yield
      ensure
        frame = @stack.pop
        emit assemble(frame)
      end

      def wrap_current_frame(head)
        frame = @stack.pop
        wrapper = new_frame
        wrapper[:body] << head
        @stack.push wrapper
        @stack.push frame
      end
        
      def emit(code)
        @stack.last[:body] << code
      end
      
      def emit_prelude(code)
        @stack.last[:prelude] << code
      end
      
      def emit_exception_handler(&block)
        proc_id = add_app_proc block
        @stack.last[:rescue_proc_id] = proc_id
      end
      
      def emit_block(conditional, &block)
        proc_id = add_app_proc block
        @stack.last[:branched] = true
        emit conditional
        add_frame &block
      end

      def add_app_proc(proc)
        id = :"proc#{@app_procs.size}"
        @app_procs[id] = proc
        id
      end
      
      def assemble_frame(frame)
        indent = 0
        lines = []
        emit_code lines, frame[:prelude], indent
        if frame[:rescue_proc_id]
          emit_code lines, 'begin', indent
          indent += 1
        end
        emit_code lines, frame[:body], indent
        if frame[:rescue_proc_id]
          emit_code lines, 'rescue => e', indent
          emit_code lines, "  app_procs[#{frame[:rescue_proc_id].inspect}].call(req, e)", indent
          emit_code lines, 'end', indent
          indent -= 1
        end
        lines
      end

      def assemble_app_proc(frame)
        indent = 0
        lines = []
        emit_code lines, frame[:prelude], indent
        emit_code lines, 'proc do |req|', indent
        emit_code lines, frame[:body], indent + 1
        emit_code lines, 'end', indent

        lines
      end

      def emit_code(lines, code, indent)
        if code.is_a? Array
          code.each { |l| emit_code lines, l, indent + 1 }
        else
          lines << (indent_line code, indent)
        end
      end

      @@indents = Hash.new { |h, k| h[k] =  '  ' * k }

      def indent_line(code, indent)
        indent == 0 ? code : "#{ @@indents[indent] }#{code}"
      end
    end
  end
end


def assemble(code)
  Tipi::Configuration::Assembler.from_source(code)
end

code = assemble <<~RUBY
gzip_response
log STDOUT
RUBY

puts code
