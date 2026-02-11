module Minimap2
  class AlignerBuilder
    @idxopt : LibMinimap2::MmIdxoptT
    @mapopt : LibMinimap2::MmMapoptT
    @threads : Int32

    def initialize
      @idxopt = LibMinimap2::MmIdxoptT.new
      @mapopt = LibMinimap2::MmMapoptT.new
      @threads = 1
      preset = Pointer(LibC::Char).null
      LibMinimap2.mm_set_opt(preset, pointerof(@idxopt), pointerof(@mapopt))
    end

    def preset(preset : String) : self
      c_preset = preset.to_unsafe
      LibMinimap2.mm_set_opt(c_preset, pointerof(@idxopt), pointerof(@mapopt))
      self
    end

    def map_ont : self
      preset("map-ont")
    end

    def map_hifi : self
      preset("map-hifi")
    end

    def map_pb : self
      preset("map-pb")
    end

    def splice : self
      preset("splice")
    end

    def splice_hq : self
      preset("splice:hq")
    end

    def splice_sr : self
      preset("splice:sr")
    end

    def asm5 : self
      preset("asm5")
    end

    def asm10 : self
      preset("asm10")
    end

    def asm20 : self
      preset("asm20")
    end

    def sr : self
      preset("sr")
    end

    def with_cigar : self
      @mapopt.flag |= MM_F_CIGAR | MM_F_OUT_CS
      self
    end

    def with_index_threads(threads : Int32) : self
      @threads = threads
      self
    end

    def with_index(path : String, output : String? = nil) : Aligner
      Aligner.new(@idxopt, @mapopt, @threads, path, output)
    end
  end
end
