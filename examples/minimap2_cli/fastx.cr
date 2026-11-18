require "compress/gzip"

module Minimap2Example
  record Read, name : String, sequence : String, quality : String? = nil

  # Streaming FASTA/FASTQ reader. Multiline sequences and qualities are accepted.
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
      while header
        unless header.starts_with?('>') || header.starts_with?('@')
          raise ArgumentError.new("Expected a FASTA/FASTQ header: #{header}")
        end
        name = header[1..].split.first?
        raise ArgumentError.new("Empty sequence name") unless name

        if header.starts_with?('>')
          read, header = fasta(input, name)
          yield read
        else
          yield fastq(input, name)
          header = next_line(input)
        end
      end
    end

    private def self.fasta(input : IO, name : String) : Tuple(Read, String?)
      sequence = String::Builder.new
      header = nil
      while line = input.gets
        break header = line if line.starts_with?('>') || line.starts_with?('@')
        sequence << line.strip
      end
      {Read.new(name, sequence.to_s), header}
    end

    private def self.fastq(input : IO, name : String) : Read
      sequence = String::Builder.new
      separator = false
      while line = input.gets
        if line.starts_with?('+')
          separator = true
          break
        end
        sequence << line.strip
      end
      raise ArgumentError.new("Missing FASTQ '+' separator for #{name}") unless separator
      bases = sequence.to_s
      quality = String::Builder.new
      # Even an empty FASTQ sequence has a quality line.
      loop do
        line = input.gets
        raise ArgumentError.new("Truncated FASTQ quality for #{name}") unless line
        quality << line
        break if quality.bytesize >= bases.bytesize
      end
      unless quality.bytesize == bases.bytesize
        raise ArgumentError.new("FASTQ sequence/quality lengths differ for #{name}")
      end
      Read.new(name, bases, quality.to_s)
    end

    private def self.next_line(input : IO) : String?
      while line = input.gets
        return line unless line.empty?
      end
      nil
    end
  end
end
