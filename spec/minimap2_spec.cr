require "./spec_helper"

def load_fasta_sequence(path : String, max_len : Int32 = 200) : String
  seq = String.build do |io|
    File.open(path) do |fh|
      fh.each_line do |line|
        next if line.empty? || line.starts_with?(">")
        chunk = line.strip
        io << chunk
        break if io.bytesize >= max_len
      end
    end
  end
  seq
end

describe Minimap2 do
  it "initializes options" do
    idxopt = Minimap2::LibMinimap2::MmIdxoptT.new
    mapopt = Minimap2::LibMinimap2::MmMapoptT.new

    preset = Pointer(LibC::Char).null
    Minimap2::LibMinimap2.mm_set_opt(preset, pointerof(idxopt), pointerof(mapopt)).should eq(0)
  end

  it "builds an index and maps a sequence" do
    ref_path = File.expand_path("./fixtures/test_data.fasta", __DIR__)
    aligner = Minimap2::Aligner.build.map_ont.with_cigar.with_index(ref_path)

    seq = load_fasta_sequence(ref_path, 100)
    seq.empty?.should eq(false)

    mappings = aligner.map(seq, cs: false, md: false)
    mappings.should be_a(Array(Minimap2::Mapping))
    mappings.size.should be > 0
    mappings[0].target_name.empty?.should eq(false)
    mappings[0].mapq.should be <= 255_u32
  end

  it "emits cs and md when requested" do
    ref_path = File.expand_path("./fixtures/test_data.fasta", __DIR__)
    aligner = Minimap2::Aligner.build.map_ont.with_cigar.with_index(ref_path)

    seq = load_fasta_sequence(ref_path, 120)
    seq.empty?.should eq(false)

    mappings = aligner.map(seq, cs: true, md: true)
    mappings.size.should be > 0
    mappings[0].cs.should_not be_nil
    mappings[0].md.should_not be_nil
  end

  it "reports sequence count" do
    ref_path = File.expand_path("./fixtures/test_data.fasta", __DIR__)
    aligner = Minimap2::Aligner.build.map_ont.with_index(ref_path)
    aligner.n_seq.should be > 0_u32
  end
end
