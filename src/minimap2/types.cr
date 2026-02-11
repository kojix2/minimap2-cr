module Minimap2
  enum Strand
    Forward
    Reverse
  end

  struct Alignment
    getter nm : Int32
    getter cigar : Array(Tuple(UInt32, UInt8))
    getter cigar_str : String
    getter md : String?
    getter cs : String?
    getter alignment_score : Int32?

    def initialize(@nm : Int32, @cigar : Array(Tuple(UInt32, UInt8)), @cigar_str : String, @md : String?, @cs : String?, @alignment_score : Int32?)
    end
  end

  struct Mapping
    getter query_start : Int32
    getter query_end : Int32
    getter strand : Strand
    getter target_name : String
    getter target_len : Int32
    getter target_start : Int32
    getter target_end : Int32
    getter match_len : Int32
    getter block_len : Int32
    getter mapq : UInt32
    getter is_primary : Bool
    getter cigar : Array(Tuple(UInt32, UInt8))
    getter nm : Int32
    getter md : String?
    getter cs : String?

    def initialize(
      @query_start : Int32,
      @query_end : Int32,
      @strand : Strand,
      @target_name : String,
      @target_len : Int32,
      @target_start : Int32,
      @target_end : Int32,
      @match_len : Int32,
      @block_len : Int32,
      @mapq : UInt32,
      @is_primary : Bool,
      @cigar : Array(Tuple(UInt32, UInt8)),
      @nm : Int32,
      @md : String?,
      @cs : String?
    )
    end
  end
end
