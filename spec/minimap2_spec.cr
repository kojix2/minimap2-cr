require "./spec_helper"

def load_fasta_sequence(path : String, max_len : Int32 = 200) : String
  seq = String.build do |io|
    File.open(path) do |file|
      file.each_line do |line|
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
    seq.empty?.should be_false

    mappings = aligner.map(seq, cs: false, md: false)
    mappings.should be_a(Array(Minimap2::Mapping))
    mappings.size.should be > 0
    mappings[0].target_name.empty?.should be_false
    mappings[0].mapq.should be <= 255_u32
  end

  it "emits cs and md when requested" do
    ref_path = File.expand_path("./fixtures/test_data.fasta", __DIR__)
    aligner = Minimap2::Aligner.build.map_ont.with_cigar.with_index(ref_path)

    seq = load_fasta_sequence(ref_path, 120)
    seq.empty?.should be_false

    mappings = aligner.map(seq, cs: true, md: true)
    mappings.size.should be > 0
    mappings[0].cs.should_not be_nil
    mappings[0].md.should_not be_nil
  end

  it "emits ds when requested" do
    ref_path = File.expand_path("./fixtures/test_data.fasta", __DIR__)
    aligner = Minimap2::Aligner.build.map_ont.with_cigar.with_index(ref_path)

    seq = load_fasta_sequence(ref_path, 120)
    seq.empty?.should be_false

    mappings = aligner.map(seq, ds: true)
    mappings.size.should be > 0
    mappings[0].ds.should_not be_nil
  end

  it "reports sequence count" do
    ref_path = File.expand_path("./fixtures/test_data.fasta", __DIR__)
    aligner = Minimap2::Aligner.build.map_ont.with_index(ref_path)
    aligner.n_seq.should be > 0_u32
  end

  it "fetches reference sequences without requiring CIGAR generation" do
    ref_path = File.expand_path("./fixtures/test_data.fasta", __DIR__)
    aligner = Minimap2::Aligner.build.map_ont.with_index(ref_path)

    aligner.seq("ref", 1, 6).should eq("CGTAC")
    aligner.seq("ref").should eq(load_fasta_sequence(ref_path))
    aligner.seq("ref", 100, 200).should eq("ACGT")
    aligner.seq("missing").should be_nil
  end

  it "returns nil for invalid reference coordinates" do
    ref_path = File.expand_path("./fixtures/test_data.fasta", __DIR__)
    aligner = Minimap2::Aligner.build.map_ont.with_cigar.with_index(ref_path)

    aligner.seq("ref", -1, 3).should be_nil
    aligner.seq("ref", 0, -1).should be_nil
    aligner.seq("ref", 5, 5).should be_nil
    aligner.seq("ref", 6, 5).should be_nil
    aligner.seq("ref", 104, 105).should be_nil
  end

  it "validates coordinates in the public fetch_seq helper" do
    ref_path = File.expand_path("./fixtures/test_data.fasta", __DIR__)
    idx = Minimap2::LibMinimap2.mm_idx_build(ref_path, 10, 15, 0, 1)
    idx.null?.should be_false
    begin
      Minimap2::LibMinimap2.mm_idx_index_name(idx)
      Minimap2.fetch_seq(idx, "ref", 1, 6).should eq("CGTAC")
      Minimap2.fetch_seq(idx, "ref", 100, 200).should eq("ACGT")
      Minimap2.fetch_seq(idx, "ref", -1, 3).should be_nil
      Minimap2.fetch_seq(idx, "ref", 0, -1).should be_nil
      Minimap2.fetch_seq(idx, "ref", 5, 5).should be_nil
      Minimap2.fetch_seq(idx, "ref", 6, 5).should be_nil
      Minimap2.fetch_seq(idx, "ref", 104, 105).should be_nil
      Minimap2.fetch_seq(idx, "missing").should be_nil
    ensure
      Minimap2::LibMinimap2.mm_idx_destroy(idx)
    end
    Minimap2.fetch_seq(Pointer(Minimap2::LibMinimap2::MmIdxT).null, "ref").should be_nil
  end

  it "handles indexes without reference sequences safely" do
    ref_path = File.expand_path("./fixtures/test_data.fasta", __DIR__)
    idxopt = Minimap2::LibMinimap2::MmIdxoptT.new
    mapopt = Minimap2::LibMinimap2::MmMapoptT.new
    null_string = Pointer(LibC::Char).null
    Minimap2::LibMinimap2.mm_set_opt(null_string, pointerof(idxopt), pointerof(mapopt))
    idxopt.flag |= Minimap2::LibMinimap2::IDX_NO_SEQ.to_i16

    File.tempfile("minimap2-cr", ".mmi") do |file|
      reader = Minimap2::LibMinimap2.mm_idx_reader_open(ref_path, pointerof(idxopt), file.path)
      reader.null?.should be_false
      begin
        idx = Minimap2::LibMinimap2.mm_idx_reader_read(reader, 1)
        idx.null?.should be_false
        begin
          Minimap2::LibMinimap2.mm_idx_index_name(idx)
          idx.value.s.null?.should be_true
          Minimap2.fetch_seq(idx, "ref", 0, 5).should be_nil
        ensure
          Minimap2::LibMinimap2.mm_idx_destroy(idx)
        end
      ensure
        Minimap2::LibMinimap2.mm_idx_reader_close(reader)
      end

      aligner = Minimap2::Aligner.build.map_ont.with_index(file.path)
      aligner.seq("ref", 0, 5).should be_nil
      seq = load_fasta_sequence(ref_path)
      aligner.map(seq).should_not be_empty

      cigar_aligner = Minimap2::Aligner.build.map_ont.with_cigar.with_index(file.path)
      cigar_aligner.seq("ref", 0, 5).should be_nil
      expect_raises(ArgumentError, "require an index with reference sequences") do
        cigar_aligner.map(seq)
      end
    end
  end
end
