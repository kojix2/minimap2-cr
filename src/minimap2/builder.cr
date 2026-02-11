module Minimap2
  class AlignerBuilder
    PRESETS = {
      map_ont:   "map-ont",
      map_hifi:  "map-hifi",
      map_pb:    "map-pb",
      splice:    "splice",
      splice_hq: "splice:hq",
      splice_sr: "splice:sr",
      asm5:      "asm5",
      asm10:     "asm10",
      asm20:     "asm20",
      sr:        "sr",
    }

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

    {% for name, value in PRESETS %}
      def {{name.id}} : self
        preset({{value}})
      end
    {% end %}

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
