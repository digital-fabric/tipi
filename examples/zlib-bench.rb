# frozen_string_literal: true

FILE_SIZES = {
  's.tmp'  => 2**10,
  'm.tmp'  => 2**17,
  'l.tmp'  => 2**20,
  'xl.tmp' => 2**24
}

def create_files
  FILE_SIZES.each { |fn, size|
    IO.write(File.join('/tmp', fn), '*' * size)
  }
end

create_files

run { |req|
  file_path = File.join('/tmp', req.path)
  if File.file?(file_path)
    req.serve_file(file_path)
  else
    req.respond(nil, ':status' => 404)
  end
}
