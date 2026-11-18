require "../../src/minimap2"
require "./fastx"

module Minimap2Example
  module Formatter
    def self.paf(output : IO, read : Read, hit : Minimap2::Mapping, cigar : Bool)
      strand = hit.strand.reverse? ? '-' : '+'
      output << read.name << '\t' << read.sequence.bytesize << '\t' << hit.query_start << '\t' << hit.query_end
      output << '\t' << strand << '\t' << hit.target_name << '\t' << hit.target_len
      output << '\t' << hit.target_start << '\t' << hit.target_end
      output << '\t' << hit.match_len << '\t' << hit.block_len << '\t' << hit.mapq
      output << "\ttp:A:" << (hit.secondary? ? 'S' : 'P')
      output << "\tcg:Z:" << hit.cigar_str if cigar
      tags(output, hit)
      output << '\n'
    end

    def self.sam_header(output : IO, references : Array(Tuple(String, Int32)))
      output.puts "@HD\tVN:1.6\tSO:unsorted"
      references.each { |(name, length)| output.puts "@SQ\tSN:#{name}\tLN:#{length}" }
      output.puts "@PG\tID:minimap2-cr\tPN:minimap2-cr\tVN:#{Minimap2::VERSION}"
    end

    def self.sam(output : IO, read : Read, hit : Minimap2::Mapping?)
      unless hit
        output.puts "#{read.name}\t4\t*\t0\t0\t*\t*\t0\t0\t#{bases_or_star(read.sequence)}\t#{bases_or_star(read.quality || "")}"
        return
      end

      reverse = hit.strand.reverse?
      flag = reverse ? 16 : 0
      flag |= 256 if hit.secondary?
      flag |= 2048 if hit.supplementary?
      left = reverse ? read.sequence.bytesize - hit.query_end : hit.query_start
      right = reverse ? hit.query_start : read.sequence.bytesize - hit.query_end
      # Supplementary records use hard clipping, as in minimap2's default SAM.
      clip = hit.supplementary? ? 'H' : 'S'
      output << read.name << '\t' << flag << '\t' << hit.target_name << '\t' << hit.target_start + 1
      output << '\t' << hit.mapq << '\t'
      output << left << clip if left > 0
      output << hit.cigar_str
      output << right << clip if right > 0
      output << "\t*\t0\t0\t"
      sam_sequence(output, read, hit, left)
      tags(output, hit)
      output << '\n'
    end

    private def self.sam_sequence(output : IO, read : Read, hit : Minimap2::Mapping, left : Int32)
      reverse = hit.strand.reverse?
      sequence = reverse ? Minimap2.revcomp(read.sequence) : read.sequence
      quality = read.quality.try { |value| reverse ? value.reverse : value }
      if hit.secondary?
        output << "*\t*"
      else
        if hit.supplementary?
          length = hit.query_end - hit.query_start
          sequence = sequence.byte_slice(left, length)
          quality = quality.try(&.byte_slice(left, length))
        end
        output << bases_or_star(sequence) << '\t' << (quality || "*")
      end
    end

    private def self.bases_or_star(sequence : String) : String
      sequence.empty? ? "*" : sequence
    end

    private def self.tags(output : IO, hit : Minimap2::Mapping)
      if nm = hit.nm
        output << "\tNM:i:" << nm
      end
      if cs = hit.cs
        output << "\tcs:Z:" << cs
      end
      if md = hit.md
        output << "\tMD:Z:" << md
      end
    end
  end
end
