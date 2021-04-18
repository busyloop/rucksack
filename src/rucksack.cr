require "openssl"

class Rucksack
  class NotFound < Exception; end

  class FileNotFound < Exception; end

  class FileCorrupted < Exception; end

  class RucksackHeaderNotFound < Exception; end

  class RucksackNotFound < Exception; end

  class RucksackEmpty < Exception; end

  class RucksackCorrupted < Exception; end

  KNAUTSCHZONE = ("\000" * 8192).to_slice
  EOF_DELIM    = "RS".to_slice
  DATA_FILE    = Process.executable_path.not_nil!
  MODE         = ENV.fetch("RUCKSACK_MODE", "0").to_i

  @@offset : Int64 = 0
  @@index = {} of String => File

  def self.offset
    return @@offset unless @@offset == 0

    file = ::File.new(Process.executable_path.not_nil!)

    loop do
      buf = Bytes.new((KNAUTSCHZONE.size).to_i)
      begin
        loop do
          bytes_read = file.read(buf)
          @@offset += bytes_read
          raise RucksackNotFound.new("Knautschzone not found") if 0 == bytes_read
          break if buf == KNAUTSCHZONE
        end

        buf = Bytes.new(1)
        loop do
          bytes_read = file.read(buf)
          @@offset += bytes_read
          raise RucksackNotFound.new("There is no Rucksack beyond the Knautschzone") if 0 == bytes_read
          next if 0 == buf[0]

          raise RucksackHeaderNotFound.new("Rucksack header not found") unless buf[0] == 61
          buf = Bytes.new(12)
          file.read(buf)
          @@offset += 12

          raise RucksackHeaderNotFound.new("Rucksack header corrupt") unless String.new(buf) == "=RUCKSACK==\n"
          break
        end
      rescue RucksackHeaderNotFound
        # Resume search if we run into a Knautschzone
        # that is not followed by a Rucksack
        next
      end
      break
    end

    @@offset
  end

  def self.build_index
    return if offset == 1
    eof = ::File.size(Process.executable_path.not_nil!)

    raise RucksackEmpty.new("Rucksack is empty, did you pack any files?") if offset + 2 > eof

    file_offset : Int64 = 0.to_i64
    ::File.open(Process.executable_path.not_nil!) do |fd|
      fd.seek(offset)
      loop do
        path_len = fd.read_bytes(UInt16, IO::ByteFormat::LittleEndian)

        path = Bytes.new(path_len)
        fd.read(path)

        size = fd.read_bytes(Int64, IO::ByteFormat::LittleEndian)
        fd.seek(offset + file_offset + 2 + path_len + 8 + size)

        body_digest = Bytes.new(32)
        fd.read(body_digest)

        delim = Bytes.new(2)
        fd.read(delim)
        raise RucksackCorrupted.new("Truncated") unless EOF_DELIM == delim

        path_str = String.new(path)
        @@index[path_str] = RucksackFile.new(path: String.new(path), offset: @@offset + file_offset + 2 + path_len + 8, size: size, checksum: body_digest)
        @@index[path_str].as(RucksackFile).verify! if MODE == 2

        file_offset += path_len
        file_offset += size
        file_offset += 2 + 8 + 32 + 2

        break if offset + file_offset == eof
        raise RucksackCorrupted.new("Out of bounds") if offset + file_offset > eof
      end
    end
  rescue RucksackNotFound
    if MODE == 0
      @@offset = 1
    else
      puts "FATAL: Rucksack not found. Did you append .rucksack to #{Process.executable_path}?"
      puts "       Run with RUCKSACK_MODE=0 if you want to fallback to direct filesystem access."
      exit 42
    end
  rescue RucksackCorrupted
    puts "FATAL: Rucksack is corrupt."
    exit 43
  end

  def self.get(path)
    build_index if @@index.empty?

    return @@index[path] if @@index.has_key?(path)

    raise FileNotFound.new("'#{path}' not found in Rucksack") unless MODE == 0
    raise FileNotFound.new("'#{path}' not found in Rucksack nor in filesystem") unless ::File.readable?(path) && ::File.file?(path)

    FilesystemFile.new(path)
  end

  class Checksummer < IO
    def initialize
      @md = OpenSSL::Digest.new("SHA256")
    end

    def read(slice : Bytes)
      raise NotImplementedError.new("")
    end

    {% if compare_versions(Crystal::VERSION, "0.35.0") == 0 %}
      def write(slice : Bytes) : Int64
        @md.update(slice)
        slice.size.to_i64
      end
    {% else %}
      def write(slice : Bytes) : Nil
        @md.update(slice)
      end
    {% end %}

    def final
      @md.final
    end
  end

  abstract class File
    abstract def read(io : IO, skip_verify = false)
    abstract def path : String
    abstract def size : Int64
    abstract def checksum : Slice(UInt8)
  end

  class FilesystemFile < File
    getter path : String

    def initialize(@path : String)
    end

    def read(io : IO, skip_verify = false)
      ::File.open(@path) do |fd|
        IO.copy(fd, io)
      end
    end

    def checksum : Slice(UInt8)
      c = Checksummer.new
      ::File.open(@path) do |fd|
        IO.copy(fd, c)
      end
      c.final
    end

    def size : Int64
      ::File.size(@path)
    end
  end

  class RucksackFile < File
    getter path : String
    getter checksum : Slice(UInt8)
    getter size : Int64

    def initialize(@path, @offset : Int64, @size, @checksum)
      @verified = false
    end

    def verify!
      c = Checksummer.new
      read(c, true)
      raise FileCorrupted.new(@path) unless @checksum == c.final
      @verified = true
    end

    def read(io : IO, skip_verify = false)
      verify! unless @verified || skip_verify
      ::File.open(Process.executable_path.not_nil!) do |fd|
        fd.seek(@offset)
        IO.copy(fd, io, @size)
      end
    end
  end
end

{{ system("rm -f #{__DIR__}/.rucksack_packer.cr .rucksack.toc") }}
{{ system("head -c 16397 /dev/zero >.rucksack") }}
{{ system("echo ==RUCKSACK== >>.rucksack") }}

macro rucksack(path)
  {% if path.is_a? StringLiteral && !path.empty? %}
  {{
    system(<<-EOC
cat >#{__DIR__}/.rucksack_packer.cr <<EOF
require "digest"

EOF_DELIM = "RS".to_slice

unless File.readable?(ARGV[0])
  puts "Rucksack ERROR: '\#{ARGV[0]}' does not exist or is not readable"
  exit 1
end

seen = File.read(".rucksack.toc") rescue ""
exit 0 if seen.includes? ARGV[0] + "\n"

dst = File.open(".rucksack", "a")
src = File.open ARGV[0]
size = src.size

dio = IO::Digest.new(dst, Digest::SHA256.new, mode: IO::Digest::DigestMode::Write)

dst.write_bytes ARGV[0].size.to_u16, IO::ByteFormat::LittleEndian
dst.write(ARGV[0].to_slice)

dst.write_bytes size.to_u64, IO::ByteFormat::LittleEndian

bytes_copied = IO.copy(src, dio)

dst.write(dio.final)
dst.write(EOF_DELIM)

if bytes_copied != size
  puts "Rucksack ERROR: I/O error while copying '\#{ARGV[0]}': \#{bytes_copied} bytes copied, \#{size} expected"
  exit 1
end

src.close
dst.close

File.open(".rucksack.toc", "a") do |fd|
  fd.puts ARGV[0]
end
EOF
EOC
    )
  }}
  {{ run("./.rucksack_packer", path) }}
  {{ system("rm -f #{__DIR__}/.rucksack_packer.cr") }}
  {% end %}
  {% if path != "" %}
    Rucksack.get({{path}})
  {% end %}
end

Rucksack.build_index
