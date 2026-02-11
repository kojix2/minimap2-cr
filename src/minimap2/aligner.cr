module Minimap2
  class Aligner
    @idxopt : LibMinimap2::MmIdxoptT
    @mapopt : LibMinimap2::MmMapoptT
    @threads : Int32
    @idx_parts : Array(Pointer(LibMinimap2::MmIdxT))

    def self.builder : AlignerBuilder
      AlignerBuilder.new
    end

    def initialize(idxopt : LibMinimap2::MmIdxoptT, mapopt : LibMinimap2::MmMapoptT, threads : Int32, path : String, output : String?)
      @idxopt = idxopt
      @mapopt = mapopt
      @threads = threads
      @idx_parts = [] of Pointer(LibMinimap2::MmIdxT)

      c_path = path.to_unsafe
      c_output = output ? output.to_unsafe : Pointer(LibC::Char).null
      reader = LibMinimap2.mm_idx_reader_open(c_path, pointerof(@idxopt), c_output)
      raise "Failed to open index or reference" if reader.null?

      begin
        loop do
          idx = LibMinimap2.mm_idx_reader_read(reader, @threads)
          break if idx.null?
          LibMinimap2.mm_idx_index_name(idx)
          @idx_parts << idx
          if @idx_parts.size == 1
            LibMinimap2.mm_mapopt_update(pointerof(@mapopt), idx)
          end
        end
      ensure
        LibMinimap2.mm_idx_reader_close(reader)
      end

      raise "Failed to build index" if @idx_parts.empty?
    end

    def n_seq : UInt32
      return 0_u32 if @idx_parts.empty?
      @idx_parts[0].value.n_seq
    end

    def map(seq : String, cs : Bool = false, md : Bool = false, max_frag_len : Int32? = nil, extra_flags : Array(UInt64)? = nil, query_name : String? = nil) : Array(Mapping)
      map(seq.to_slice, cs, md, max_frag_len, extra_flags, query_name)
    end

    def map(seq : Bytes, cs : Bool = false, md : Bool = false, max_frag_len : Int32? = nil, extra_flags : Array(UInt64)? = nil, query_name : String? = nil) : Array(Mapping)
      raise "Sequence is empty" if seq.empty?

      mapopt = @mapopt
      mapopt.max_frag_len = max_frag_len if max_frag_len
      if extra_flags
        extra_flags.each { |flag| mapopt.flag |= flag.to_i64 }
      end

      qname_ptr = query_name ? query_name.to_unsafe : Pointer(LibC::Char).null

      tbuf = LibMinimap2.mm_tbuf_init
      raise "Failed to init thread buffer" if tbuf.null?

      begin
        km = LibMinimap2.mm_tbuf_get_km(tbuf)
        all_mappings = [] of Mapping

        @idx_parts.each do |idx|
          n_regs = 0
          reg_ptr = LibMinimap2.mm_map(idx, seq.size, seq.to_unsafe.as(LibC::Char*), pointerof(n_regs), tbuf, pointerof(mapopt), qname_ptr)
          next if reg_ptr.null? || n_regs == 0

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
            alignment_score : Int32? = nil

            if !reg.p.null?
              extra_ptr = reg.p
              extra = extra_ptr.value
              n_ambi = (extra.n_ambi_trans & 0x3fffffff_u32).to_i
              nm = reg.blen - reg.mlen + n_ambi
              alignment_score = extra.dp_score

              if extra.n_cigar > 0
                cigar_ptr = (extra_ptr.as(Pointer(UInt8)) + (sizeof(LibMinimap2::MmExtraT) - sizeof(UInt32))).as(Pointer(UInt32))
                extra.n_cigar.times do |j|
                  entry = cigar_ptr[j]
                  len = entry >> 4
                  op = (entry & 0xf_u32).to_u8
                  cigar << {len, op}
                  cigar_str += "#{len}#{self.class.cigar_op_char(op)}"
                end
              end

              if cs
                cs_str = gen_cs(km, idx, regs + i, seq)
              end
              if md
                md_str = gen_md(km, idx, regs + i, seq)
              end

              LibC.free(reg.p.as(Void*))
            end

            all_mappings << Mapping.new(
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
              nm,
              md_str,
              cs_str
            )
          end

          LibC.free(reg_ptr.as(Void*))
        end

        all_mappings
      ensure
        LibMinimap2.mm_tbuf_destroy(tbuf)
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

    private def gen_cs(km : Void*, idx : Pointer(LibMinimap2::MmIdxT), reg_ptr : Pointer(LibMinimap2::MmReg1T), seq : Bytes) : String
      buf = Pointer(LibC::Char).null
      max_len = 0
      LibMinimap2.mm_gen_cs(km, pointerof(buf), pointerof(max_len), idx, reg_ptr, seq.to_unsafe.as(LibC::Char*), 1)
      return "" if buf.null?
      begin
        String.new(buf)
      ensure
        LibC.free(buf.as(Void*))
      end
    end

    private def gen_md(km : Void*, idx : Pointer(LibMinimap2::MmIdxT), reg_ptr : Pointer(LibMinimap2::MmReg1T), seq : Bytes) : String
      buf = Pointer(LibC::Char).null
      max_len = 0
      LibMinimap2.mm_gen_MD(km, pointerof(buf), pointerof(max_len), idx, reg_ptr, seq.to_unsafe.as(LibC::Char*))
      return "" if buf.null?
      begin
        String.new(buf)
      ensure
        LibC.free(buf.as(Void*))
      end
    end
  end
end
