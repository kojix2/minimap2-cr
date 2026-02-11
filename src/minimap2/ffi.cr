module Minimap2
  MM_F_CIGAR  = 0x004_i64
  MM_F_OUT_CS = 0x040_i64

  @[Link(ldflags: "-Wl,-rpath,#{__DIR__}/../../ext -L#{__DIR__}/../../ext -lminimap2 -lm -lz -lpthread")]
  lib LibMinimap2
    type MmIdxReaderT = Void
    type MmTbufT = Void

    struct MmIdxSeqT
      name : LibC::Char*
      offset : UInt64
      len : UInt32
      is_alt : UInt32
    end

    struct MmIdxT
      b : Int32
      w : Int32
      k : Int32
      flag : Int32
      n_seq : UInt32
      index : Int32
      n_alt : Int32
      seq : MmIdxSeqT*
      s : UInt32*
      b_ptr : Void*
      i_ptr : Void*
      spsc : Void*
      j_ptr : Void*
      km : Void*
      h : Void*
    end

    struct MmExtraT
      capacity : UInt32
      dp_score : Int32
      dp_max : Int32
      dp_max2 : Int32
      dp_max0 : Int32
      n_ambi_trans : UInt32
      n_cigar : UInt32
      cigar : UInt32
    end

    struct MmReg1T
      id : Int32
      cnt : Int32
      rid : Int32
      score : Int32
      qs : Int32
      qe : Int32
      rs : Int32
      re : Int32
      parent : Int32
      subsc : Int32
      as : Int32
      mlen : Int32
      blen : Int32
      n_sub : Int32
      score0 : Int32
      flags : UInt32
      hash : UInt32
      div : Float32
      p : MmExtraT*
    end

    struct MmIdxoptT
      k : Int16
      w : Int16
      flag : Int16
      bucket_bits : Int16
      mini_batch_size : Int64
      batch_size : UInt64
    end

    struct MmMapoptT
      flag : Int64
      seed : Int32
      sdust_thres : Int32
      max_qlen : Int32
      bw : Int32
      bw_long : Int32
      max_gap : Int32
      max_gap_ref : Int32
      max_frag_len : Int32
      max_chain_skip : Int32
      max_chain_iter : Int32
      min_cnt : Int32
      min_chain_score : Int32
      chain_gap_scale : Float32
      chain_skip_scale : Float32
      rmq_size_cap : Int32
      rmq_inner_dist : Int32
      rmq_rescue_size : Int32
      rmq_rescue_ratio : Float32
      mask_level : Float32
      mask_len : Int32
      pri_ratio : Float32
      best_n : Int32
      alt_drop : Float32
      a : Int32
      b : Int32
      q : Int32
      e : Int32
      q2 : Int32
      e2 : Int32
      transition : Int32
      sc_ambi : Int32
      noncan : Int32
      junc_bonus : Int32
      junc_pen : Int32
      zdrop : Int32
      zdrop_inv : Int32
      end_bonus : Int32
      min_dp_max : Int32
      min_ksw_len : Int32
      anchor_ext_len : Int32
      anchor_ext_shift : Int32
      max_clip_ratio : Float32
      rank_min_len : Int32
      rank_frac : Float32
      pe_ori : Int32
      pe_bonus : Int32
      jump_min_match : Int32
      mid_occ_frac : Float32
      q_occ_frac : Float32
      min_mid_occ : Int32
      max_mid_occ : Int32
      mid_occ : Int32
      max_occ : Int32
      max_max_occ : Int32
      occ_dist : Int32
      mini_batch_size : Int64
      max_sw_mat : Int64
      cap_kalloc : Int64
      split_prefix : LibC::Char*
    end

    fun mm_set_opt(preset : LibC::Char*, io : MmIdxoptT*, mo : MmMapoptT*) : Int32
    fun mm_check_opt(io : MmIdxoptT*, mo : MmMapoptT*) : Int32
    fun mm_mapopt_update(opt : MmMapoptT*, mi : MmIdxT*) : Void
    fun mm_mapopt_max_intron_len(opt : MmMapoptT*, max_intron_len : Int32) : Void

    fun mm_idxopt_init(opt : MmIdxoptT*) : Void
    fun mm_mapopt_init(opt : MmMapoptT*) : Void

    fun mm_idx_reader_open(fn : LibC::Char*, opt : MmIdxoptT*, fn_out : LibC::Char*) : MmIdxReaderT*
    fun mm_idx_reader_read(r : MmIdxReaderT*, n_threads : Int32) : MmIdxT*
    fun mm_idx_reader_close(r : MmIdxReaderT*) : Void
    fun mm_idx_reader_eof(r : MmIdxReaderT*) : Int32
    fun mm_idx_is_idx(fn : LibC::Char*) : Int64
    fun mm_idx_load(fp : Void*) : MmIdxT*
    fun mm_idx_dump(fp : Void*, mi : MmIdxT*) : Void
    fun mm_idx_str(w : Int32, k : Int32, is_hpc : Int32, bucket_bits : Int32, n : Int32, seq : LibC::Char**, name : LibC::Char**) : MmIdxT*
    fun mm_idx_stat(idx : MmIdxT*) : Void
    fun mm_idx_index_name(mi : MmIdxT*) : Int32
    fun mm_idx_name2id(mi : MmIdxT*, name : LibC::Char*) : Int32
    fun mm_idx_getseq(mi : MmIdxT*, rid : UInt32, st : UInt32, en : UInt32, seq : UInt8*) : Int32
    fun mm_idx_alt_read(mi : MmIdxT*, fn : LibC::Char*) : Int32
    fun mm_idx_bed_read(mi : MmIdxT*, fn : LibC::Char*, read_junc : Int32) : Int32
    fun mm_idx_bed_junc(mi : MmIdxT*, ctg : Int32, st : Int32, en : Int32, s : UInt8*) : Int32
    fun mm_max_spsc_bonus(mo : MmMapoptT*) : Int32
    fun mm_idx_spsc_read(idx : MmIdxT*, fn : LibC::Char*, max_sc : Int32) : Int32
    fun mm_idx_spsc_read2(idx : MmIdxT*, fn : LibC::Char*, max_sc : Int32, scale : Float32) : Int32
    fun mm_idx_spsc_get(db : MmIdxT*, cid : Int32, st0 : Int64, en0 : Int64, rev : Int32, sc : UInt8*) : Int64

    fun mm_idx_destroy(mi : MmIdxT*) : Void

    fun mm_tbuf_init : MmTbufT*
    fun mm_tbuf_destroy(b : MmTbufT*) : Void
    fun mm_tbuf_get_km(b : MmTbufT*) : Void*

    fun mm_map(mi : MmIdxT*, l_seq : Int32, seq : LibC::Char*, n_regs : Int32*, b : MmTbufT*, opt : MmMapoptT*, name : LibC::Char*) : MmReg1T*
    fun mm_map_frag(mi : MmIdxT*, n_segs : Int32, qlens : Int32*, seqs : LibC::Char**, n_regs : Int32*, regs : MmReg1T**, b : MmTbufT*, opt : MmMapoptT*, qname : LibC::Char*) : Void
    fun mm_map_file(idx : MmIdxT*, fn : LibC::Char*, opt : MmMapoptT*, n_threads : Int32) : Int32
    fun mm_map_file_frag(idx : MmIdxT*, n_segs : Int32, fn : LibC::Char**, opt : MmMapoptT*, n_threads : Int32) : Int32
    fun mm_gen_cs(km : Void*, buf : LibC::Char**, max_len : Int32*, mi : MmIdxT*, r : MmReg1T*, seq : LibC::Char*, no_iden : Int32) : Int32
    fun mm_gen_MD(km : Void*, buf : LibC::Char**, max_len : Int32*, mi : MmIdxT*, r : MmReg1T*, seq : LibC::Char*) : Int32

    fun mm_idx_build(fn : LibC::Char*, w : Int32, k : Int32, flag : Int32, n_threads : Int32) : MmIdxT*
  end
end
