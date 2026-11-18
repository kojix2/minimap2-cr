require "compress/gzip"
require "fastx"

module Minimap2Example
  record Read, name : String, sequence : String, quality : String? = nil

  private class PrefixedInput < IO
    def initialize(prefix : String, @input : IO)
      @prefix = IO::Memory.new(prefix)
    end

    def read(slice : Bytes) : Int32
      count = @prefix.read(slice)
      count == 0 ? @input.read(slice) : count
    end

    def write(slice : Bytes) : Nil
      raise IO::Error.new("Input is read-only")
    end
  end

  # Input detection and CLI record names around fastx.cr's streaming readers.
  module Fastx
    def self.each(path : String, &block : Read ->)
      if path == "-"
        each_io(STDIN, &block)
      else
        File.open(path) do |file|
          magic = Bytes.new(2)
          count = file.read(magic)
          file.rewind
          if count == 2 && magic == Bytes[0x1f, 0x8b]
            Compress::Gzip::Reader.open(file) { |gzip| each_io(gzip, &block) }
          else
            each_io(file, &block)
          end
        end
      end
    end

    def self.each_io(input : IO, & : Read ->)
      header = next_line(input)
      return unless header
      # Replay the header without seeking, so pipes and gzip streams work too.
      source = PrefixedInput.new(header + "\n", input)
      if header.starts_with?('>')
        ::Fastx::Fasta::Reader.open(source) do |reader|
          reader.each do |name, sequence|
            yield Read.new(read_name(name), sequence)
          end
        end
      elsif header.starts_with?('@')
        ::Fastx::Fastq::Reader.open(source) do |reader|
          reader.each do |name, sequence, quality|
            yield Read.new(read_name(name), sequence, quality)
          end
        end
      else
        raise ArgumentError.new("Expected a FASTA/FASTQ header: #{header}")
      end
    end

    private def self.read_name(header : String) : String
      header.split.first? || raise ArgumentError.new("Empty sequence name")
    end

    private def self.next_line(input : IO) : String?
      while line = input.gets
        return line unless line.empty?
      end
      nil
    end
  end
end
