module Minimap2
  class Aligner
    getter idx_opt : LibMinimap2::MmIdxoptT
    getter map_opt : LibMinimap2::MmMapoptT

    @idxopt : LibMinimap2::MmIdxoptT
    @mapopt : LibMinimap2::MmMapoptT
    @threads : Int32
    @idx_parts : Array(Pointer(LibMinimap2::MmIdxT))

    def self.build : AlignerBuilder
      AlignerBuilder.new
    end

    @[Deprecated("Use .build instead")]
    def self.builder : AlignerBuilder
      build
    end

    def self.new(path : String, preset : String? = nil, threads : Int32 = 1, output : String? = nil, cigar : Bool = false)
      builder = AlignerBuilder.new
      builder.preset(preset) if preset
      builder.with_index_threads(threads)
      builder.with_cigar if cigar
      builder.with_index(path, output)
    end

    def self.new(path : String, preset : String? = nil, threads : Int32 = 1, output : String? = nil, cigar : Bool = false, &block : AlignerBuilder ->)
      builder = AlignerBuilder.new
      builder.preset(preset) if preset
      builder.with_index_threads(threads)
      builder.with_cigar if cigar
      block.call(builder)
      builder.with_index(path, output)
    end

    def initialize(idxopt : LibMinimap2::MmIdxoptT, mapopt : LibMinimap2::MmMapoptT, threads : Int32, path : String, output : String?)
      @idxopt = idxopt
      @mapopt = mapopt
      @threads = threads
      @idx_parts = [] of Pointer(LibMinimap2::MmIdxT)

      reader = open_index_reader(path, output)
      begin
        load_indices(reader)
        update_mapopt_if_needed
      ensure
        LibMinimap2.mm_idx_reader_close(reader)
      end

      raise "Failed to build index" if @idx_parts.empty?
    end

    def n_seq : UInt32
      return 0_u32 if @idx_parts.empty?
      @idx_parts[0].value.n_seq
    end

    def seq(name : String, start : Int32 = 0, stop : Int32 = Int32::MAX) : String?
      return nil if @idx_parts.empty?

      @idx_parts.each do |idx|
        next if idx.null?
        next if (@mapopt.flag & 4_i64) == 0_i64 && (idx.value.flag & 2) == 0

        rid = LibMinimap2.mm_idx_name2id(idx, name)
        next if rid < 0

        seq_entry = idx.value.seq + rid
        seq_len = seq_entry.value.len.to_i
        return nil if start >= seq_len || start >= stop

        en = stop
        en = seq_len if en < 0 || en > seq_len

        buf = Bytes.new(en - start)
        got = LibMinimap2.mm_idx_getseq(idx, rid.to_u32, start.to_u32, en.to_u32, buf.to_unsafe)
        next if got <= 0

        return decode_seq(buf, got)
      end

      nil
    end

    def map(seq : String, cs : Bool = false, md : Bool = false, max_frag_len : Int32? = nil, extra_flags : Array(UInt64)? = nil, query_name : String? = nil) : Array(Mapping)
      map(seq.to_slice, cs, md, max_frag_len, extra_flags, query_name)
    end

    def map(seq : Bytes, cs : Bool = false, md : Bool = false, max_frag_len : Int32? = nil, extra_flags : Array(UInt64)? = nil, query_name : String? = nil) : Array(Mapping)
      raise "Sequence is empty" if seq.empty?
      mapopt = prepare_mapopt(max_frag_len, extra_flags)
      qname_ptr = query_name ? query_name.to_unsafe : Pointer(LibC::Char).null

      with_thread_buffer do |tbuf|
        km = LibMinimap2.mm_tbuf_get_km(tbuf)
        all_mappings = [] of Mapping

        @idx_parts.each do |idx|
          all_mappings.concat(map_with_index(idx, seq, mapopt, tbuf, qname_ptr, km, cs, md))
        end

        all_mappings
      end
    end

    def finalize
      @idx_parts.each do |idx|
        LibMinimap2.mm_idx_destroy(idx)
      end
    end

    def self.cigar_op_char(op : UInt8) : Char
      case op
      when 0
        'M'
      when 1
        'I'
      when 2
        'D'
      when 3
        'N'
      when 4
        'S'
      when 5
        'H'
      when 6
        'P'
      when 7
        '='
      when 8
        'X'
      else
        '?'
      end
    end

    private def open_index_reader(path : String, output : String?)
      c_path = path.to_unsafe
      c_output = output ? output.to_unsafe : Pointer(LibC::Char).null
      reader = LibMinimap2.mm_idx_reader_open(c_path, pointerof(@idxopt), c_output)
      raise "Failed to open index or reference" if reader.null?
      reader
    end

    private def load_indices(reader)
      loop do
        idx = LibMinimap2.mm_idx_reader_read(reader, @threads)
        break if idx.null?
        LibMinimap2.mm_idx_index_name(idx)
        @idx_parts << idx
      end
    end

    private def update_mapopt_if_needed
      return if @idx_parts.empty?
      LibMinimap2.mm_mapopt_update(pointerof(@mapopt), @idx_parts.first)
    end

    private def prepare_mapopt(max_frag_len : Int32?, extra_flags : Array(UInt64)?)
      mapopt = @mapopt
      mapopt.max_frag_len = max_frag_len if max_frag_len
      if extra_flags
        extra_flags.each { |flag| mapopt.flag |= flag.to_i64 }
      end
      mapopt
    end

    private def with_thread_buffer(&)
      tbuf = LibMinimap2.mm_tbuf_init
      raise "Failed to init thread buffer" if tbuf.null?

      begin
        yield tbuf
      ensure
        LibMinimap2.mm_tbuf_destroy(tbuf)
      end
    end

    private def map_with_index(idx : Pointer(LibMinimap2::MmIdxT), seq : Bytes, mapopt : LibMinimap2::MmMapoptT, tbuf, qname_ptr : Pointer(LibC::Char), km : Void*, cs : Bool, md : Bool) : Array(Mapping)
      n_regs = 0
      reg_ptr = LibMinimap2.mm_map(idx, seq.size, seq.to_unsafe.as(LibC::Char*), pointerof(n_regs), tbuf, pointerof(mapopt), qname_ptr)
      return [] of Mapping if reg_ptr.null? || n_regs == 0

      mappings = [] of Mapping

      begin
        regs = reg_ptr.as(Pointer(LibMinimap2::MmReg1T))
        0.upto(n_regs - 1) do |i|
          reg = regs[i]
          next if reg.rid < 0

          seq_entry = idx.value.seq + reg.rid
          target_name = String.new(seq_entry.value.name)
          target_len = seq_entry.value.len.to_i

          flags = reg.flags
          mapq = (flags & 0xff_u32)
          rev = ((flags >> 10) & 0x1_u32) == 1_u32
          sam_pri = ((flags >> 12) & 0x1_u32) == 1_u32
          is_primary = reg.parent == reg.id && sam_pri

          strand = rev ? Strand::Reverse : Strand::Forward

          cigar = [] of Tuple(UInt32, UInt8)
          cigar_str = ""
          nm = 0
          md_str : String? = nil
          cs_str : String? = nil

          if !reg.p.null?
            extra_ptr = reg.p
            extra = extra_ptr.value
            n_ambi = (extra.n_ambi_trans & 0x3fffffff_u32).to_i
            nm = reg.blen - reg.mlen + n_ambi

            cigar = parse_cigar(extra_ptr)
            cigar_str = build_cigar_string(cigar)

            if cs
              cs_str = gen_cs(km, idx, regs + i, seq)
            end
            if md
              md_str = gen_md(km, idx, regs + i, seq)
            end

            LibC.free(reg.p.as(Void*))
          end

          mappings << Mapping.new(
            reg.qs,
            reg.qe,
            strand,
            target_name,
            target_len,
            reg.rs,
            reg.re,
            reg.mlen,
            reg.blen,
            mapq,
            is_primary,
            cigar,
            cigar_str,
            nm,
            md_str,
            cs_str
          )
        end
      ensure
        LibC.free(reg_ptr.as(Void*))
      end

      mappings
    end

    private def gen_md(km : Void*, idx : Pointer(LibMinimap2::MmIdxT), reg_ptr : Pointer(LibMinimap2::MmReg1T), seq : Bytes) : String
      generate_string(km, idx, reg_ptr, seq) do |km, buf, max_len, idx, reg_ptr, seq|
        LibMinimap2.mm_gen_MD(km, buf, max_len, idx, reg_ptr, seq)
      end
    end

    private def build_cigar_string(cigar : Array(Tuple(UInt32, UInt8))) : String
      return "" if cigar.empty?

      String.build do |io|
        cigar.each do |(len, op)|
          io << len << self.class.cigar_op_char(op)
        end
      end
    end

    private def decode_seq(buf : Bytes, len : Int32) : String
      bases = "ACGTN"
      String.build do |io|
        len.times do |i|
          io << bases[buf[i].to_i]
        end
      end
    end

    private def parse_cigar(extra_ptr : Pointer(LibMinimap2::MmExtraT)) : Array(Tuple(UInt32, UInt8))
      extra = extra_ptr.value
      return [] of Tuple(UInt32, UInt8) if extra.n_cigar == 0

      cigar_ops = [] of Tuple(UInt32, UInt8)
      cigar_ptr = (extra_ptr.as(Pointer(UInt8)) + (sizeof(LibMinimap2::MmExtraT) - sizeof(UInt32))).as(Pointer(UInt32))
      extra.n_cigar.times do |j|
        entry = cigar_ptr[j]
        len = entry >> 4
        op = (entry & 0xf_u32).to_u8
        cigar_ops << {len, op}
      end

      cigar_ops
    end

    private def generate_string(km : Void*, idx : Pointer(LibMinimap2::MmIdxT), reg_ptr : Pointer(LibMinimap2::MmReg1T), seq : Bytes, &block : (Void*, Pointer(LibC::Char)*, Int32*, Pointer(LibMinimap2::MmIdxT), Pointer(LibMinimap2::MmReg1T), LibC::Char*) ->)
      buf = Pointer(LibC::Char).null
      max_len = 0
      block.call(km, pointerof(buf), pointerof(max_len), idx, reg_ptr, seq.to_unsafe.as(LibC::Char*))
      return "" if buf.null?
      begin
        String.new(buf)
      ensure
        LibC.free(buf.as(Void*))
      end
    end

    private def gen_cs(km : Void*, idx : Pointer(LibMinimap2::MmIdxT), reg_ptr : Pointer(LibMinimap2::MmReg1T), seq : Bytes) : String
      generate_string(km, idx, reg_ptr, seq) do |km, buf, max_len, idx, reg_ptr, seq|
        LibMinimap2.mm_gen_cs(km, buf, max_len, idx, reg_ptr, seq, 1)
      end
    end
  end
end
