module Minimap2
  def self.revcomp(seq : String) : String
    revcomp(seq.to_slice)
  end

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
    when 'A'.ord
      'T'
    when 'C'.ord
      'G'
    when 'G'.ord
      'C'
    when 'T'.ord
      'A'
    when 'U'.ord
      'A'
    when 'R'.ord
      'Y'
    when 'Y'.ord
      'R'
    when 'S'.ord
      'S'
    when 'W'.ord
      'W'
    when 'K'.ord
      'M'
    when 'M'.ord
      'K'
    when 'B'.ord
      'V'
    when 'D'.ord
      'H'
    when 'H'.ord
      'D'
    when 'V'.ord
      'B'
    when 'N'.ord
      'N'
    when 'a'.ord
      't'
    when 'c'.ord
      'g'
    when 'g'.ord
      'c'
    when 't'.ord
      'a'
    when 'u'.ord
      'a'
    when 'r'.ord
      'y'
    when 'y'.ord
      'r'
    when 's'.ord
      's'
    when 'w'.ord
      'w'
    when 'k'.ord
      'm'
    when 'm'.ord
      'k'
    when 'b'.ord
      'v'
    when 'd'.ord
      'h'
    when 'h'.ord
      'd'
    when 'v'.ord
      'b'
    when 'n'.ord
      'n'
    else
      'N'
    end
  end
end
