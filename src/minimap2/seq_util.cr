module Minimap2
  # :nodoc:
  COMPLEMENT_TABLE = begin
    bases = "ACGTURYSWKMBDHVNacgturyswkmbdhvn"
    complements = "TGCAAYRSWMKVHDBNtgcaayrswmkvhdbn"
    StaticArray(Char, 256).new do |byte|
      index = bases.index(byte.chr)
      index ? complements[index] : 'N'
    end
  end

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
  # Coordinates are 0-based, half-open (`start...stop`). Returns `nil` for
  # invalid ranges, missing contigs, or indexes without reference sequences.
  def self.fetch_seq(idx : Pointer(LibMinimap2::MmIdxT), name : String, start : Int32 = 0, stop : Int32 = Int32::MAX) : String?
    return if idx.null?
    return if (idx.value.flag & LibMinimap2::IDX_NO_SEQ) != 0 || idx.value.s.null?
    return if start < 0 || start >= stop

    rid = LibMinimap2.mm_idx_name2id(idx, name)
    return if rid < 0

    seq_entry = idx.value.seq + rid
    seq_len = seq_entry.value.len.to_i
    return if start >= seq_len

    en = stop
    en = seq_len if en > seq_len

    buf = Bytes.new(en - start)
    got = LibMinimap2.mm_idx_getseq(idx, rid.to_u32, start.to_u32, en.to_u32, buf.to_unsafe)
    return if got <= 0

    decode_seq(buf, got)
  end

  # Build an in-memory index from a single sequence.
  #
  # Useful for tests and small ad-hoc alignment tasks.
  def self.idx_seq(seq : String, w : Int32, k : Int32, is_hpc : Bool = false, bucket_bits : Int32 = 14) : Pointer(LibMinimap2::MmIdxT)
    # mm_idx_str copies the strings. Keep the pointer slots on the stack;
    # Pointer.malloc uses Crystal's GC and must never be passed to LibC.free.
    sequence = seq.to_unsafe
    name = "N/A".to_unsafe
    LibMinimap2.mm_idx_str(w, k, is_hpc ? 1 : 0, bucket_bits, 1, pointerof(sequence), pointerof(name))
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
    COMPLEMENT_TABLE[byte]
  end
end
