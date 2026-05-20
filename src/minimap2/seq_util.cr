module Minimap2
  # Utilities adapted from minimap2 mappy helpers.
  #
  # Returns the reverse-complement of a DNA/RNA sequence string.
  def self.revcomp(seq : String) : String
    revcomp(seq.to_slice)
  end

  # Returns the reverse-complement of a sequence byte slice.
  def self.revcomp(seq : Bytes) : String
    return "" if seq.empty?

    String.build do |io|
      i = seq.size - 1
      while i >= 0
        io << complement(seq[i])
        i -= 1
      end
    end
  end

  # Fetch a subsequence from an index by contig name.
  #
  # Coordinates are 0-based, half-open (`start...stop`).
  def self.fetch_seq(idx : Pointer(LibMinimap2::MmIdxT), name : String, start : Int32 = 0, stop : Int32 = Int32::MAX) : String?
    return nil if idx.null?

    rid = LibMinimap2.mm_idx_name2id(idx, name)
    return nil if rid < 0

    seq_entry = idx.value.seq + rid
    seq_len = seq_entry.value.len.to_i
    return nil if start >= seq_len || start >= stop

    en = stop
    en = seq_len if en < 0 || en > seq_len

    buf = Bytes.new(en - start)
    got = LibMinimap2.mm_idx_getseq(idx, rid.to_u32, start.to_u32, en.to_u32, buf.to_unsafe)
    return nil if got <= 0

    decode_seq(buf, got)
  end

  # Build an in-memory index from a single sequence.
  #
  # Useful for tests and small ad-hoc alignment tasks.
  def self.idx_seq(seq : String, w : Int32, k : Int32, is_hpc : Bool = false, bucket_bits : Int32 = 14) : Pointer(LibMinimap2::MmIdxT)
    bytes = seq.to_slice
    buf = Bytes.new(bytes.size + 1)
    buf.copy_from(bytes)
    buf[bytes.size] = 0_u8

    seq_ptrs = Pointer(LibC::Char*).malloc(1)
    name_ptrs = Pointer(LibC::Char*).malloc(1)

    begin
      seq_ptrs[0] = buf.to_unsafe.as(LibC::Char*)
      fake_name = "N/A"
      name_ptrs[0] = fake_name.to_unsafe
      LibMinimap2.mm_idx_str(w, k, is_hpc ? 1 : 0, bucket_bits, 1, seq_ptrs, name_ptrs)
    ensure
      LibC.free(seq_ptrs.as(Void*))
      LibC.free(name_ptrs.as(Void*))
    end
  end

  private def self.decode_seq(buf : Bytes, len : Int32) : String
    bases = "ACGTN"
    String.build do |io|
      len.times do |i|
        io << bases[buf[i].to_i]
      end
    end
  end

  private def self.complement(byte : UInt8) : Char
    case byte
    when 'A'.ord then 'T'
    when 'C'.ord then 'G'
    when 'G'.ord then 'C'
    when 'T'.ord then 'A'
    when 'U'.ord then 'A'
    when 'R'.ord then 'Y'
    when 'Y'.ord then 'R'
    when 'S'.ord then 'S'
    when 'W'.ord then 'W'
    when 'K'.ord then 'M'
    when 'M'.ord then 'K'
    when 'B'.ord then 'V'
    when 'D'.ord then 'H'
    when 'H'.ord then 'D'
    when 'V'.ord then 'B'
    when 'N'.ord then 'N'
    when 'a'.ord then 't'
    when 'c'.ord then 'g'
    when 'g'.ord then 'c'
    when 't'.ord then 'a'
    when 'u'.ord then 'a'
    when 'r'.ord then 'y'
    when 'y'.ord then 'r'
    when 's'.ord then 's'
    when 'w'.ord then 'w'
    when 'k'.ord then 'm'
    when 'm'.ord then 'k'
    when 'b'.ord then 'v'
    when 'd'.ord then 'h'
    when 'h'.ord then 'd'
    when 'v'.ord then 'b'
    when 'n'.ord then 'n'
    else 'N'
    end
  end
end
