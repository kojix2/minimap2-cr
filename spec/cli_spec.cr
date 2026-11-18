require "./spec_helper"
require "../examples/minimap2_cli/cli"

private def cli(args : Array(String)) : Tuple(Int32, String, String)
  output = IO::Memory.new
  error = IO::Memory.new
  status = Minimap2Example::CLI.run(args, output, error)
  {status, output.to_s, error.to_s}
end

private def with_cli_reference(& : String, String, String ->)
  rng = Random.new(4321)
  reference = String.build { |io| 6000.times { io << "ACGT"[rng.rand(4)] } }
  File.tempfile("minimap2-cli-ref", ".fa") do |ref|
    ref.puts ">ref\n#{reference}"
    ref.flush
    File.tempfile("minimap2-cli-query", ".fa") do |query|
      query.puts ">read description\n#{reference[500, 1500]}\n>unmapped\n#{"N" * 500}"
      query.flush
      yield ref.path, query.path, reference
    end
  end
end

describe Minimap2Example::Fastx do
  it "reads multiline FASTA and FASTQ with comments, CRLF and header-like quality" do
    reads = [] of Minimap2Example::Read
    input = IO::Memory.new("\n>one comment\r\nAC\r\nGT\r\n@two comment\nAC\nGT\n+two\n@@\n>>\n")
    Minimap2Example::Fastx.each_io(input) { |read| reads << read }
    reads.should eq([
      Minimap2Example::Read.new("one", "ACGT"),
      Minimap2Example::Read.new("two", "ACGT", "@@>>"),
    ])
  end

  it "reads gzip input by magic bytes rather than filename suffix" do
    File.tempfile("minimap2-fastx", ".data") do |file|
      Compress::Gzip::Writer.open(file) { |gzip| gzip << ">gzip\nACGT\n" }
      file.flush
      reads = [] of Minimap2Example::Read
      Minimap2Example::Fastx.each(file.path) { |read| reads << read }
      reads.should eq([Minimap2Example::Read.new("gzip", "ACGT")])
    end
  end

  it "rejects malformed headers, missing separators and incorrect quality lengths" do
    ["ACGT\n", ">\nACGT\n", "@read\nACGT\n", "@read\nACGT\n+\n!!\n", "@read\nACGT\n+\n!!!!!\n"].each do |text|
      expect_raises(ArgumentError) do
        Minimap2Example::Fastx.each_io(IO::Memory.new(text)) { |_| }
      end
    end
  end

  it "preserves empty FASTA and FASTQ records" do
    reads = [] of Minimap2Example::Read
    Minimap2Example::Fastx.each_io(IO::Memory.new(">empty\n@empty2\n\n+\n\n")) { |read| reads << read }
    reads.map(&.sequence).should eq(["", ""])
  end
end

describe Minimap2Example::CLI do
  it "shows help/version and reports invalid options or missing arguments" do
    cli(["--help"])[1].should contain("Usage: minimap2-cr")
    cli(["--version"])[1].strip.should eq(Minimap2::VERSION)
    [[] of String, ["--unknown"], ["ref.fa"], ["-t", "0", "ref", "query"], ["-t", "invalid", "ref", "query"], ["--secondary=maybe", "ref", "query"]].each do |args|
      status, output, error = cli(args)
      status.should eq(1)
      output.should be_empty
      error.should start_with("minimap2-cr:")
    end
  end

  it "writes PAF with zero-based coordinates, CIGAR and requested tags" do
    with_cli_reference do |ref, query, _|
      status, output, error = cli(["-x", "map-ont", "-c", "--cs", "--MD", ref, query])
      status.should eq(0)
      error.should be_empty
      fields = output.lines.first.split('\t')
      fields[0, 12].should eq(%w[read 1500 0 1500 + ref 6000 500 2000 1500 1500 60])
      ["cg:Z:1500M", "NM:i:0", "cs:Z::1500", "MD:Z:1500"].each { |tag| fields.should contain(tag) }
      output.lines.size.should eq(1)
    end
  end

  it "writes unmapped SAM and reverse-strand sequence, clipping and qualities" do
    with_cli_reference do |ref, query, reference|
      sequence = Minimap2.revcomp(reference[500, 1500])
      quality = "!" * 700 + "I" * 800
      File.write(query, "@reverse\n#{sequence}\n+\n#{quality}\n@unmapped\nNNNN\n+\n!!!!\n")
      status, output, error = cli(["-ax", "map-ont", ref, query])
      status.should eq(0)
      error.should be_empty
      output.should contain("@SQ\tSN:ref\tLN:6000\n")
      records = output.lines.reject(&.starts_with?('@')).map(&.split('\t'))
      records.first[0, 6].should eq(%w[reverse 16 ref 501 60 1500M])
      records.first[9].should eq(reference[500, 1500])
      records.first[10].should eq(quality.reverse)
      records.last[0, 11].should eq(%w[unmapped 4 * 0 0 * * 0 0 NNNN !!!!])
    end
  end

  it "builds and reloads interoperable MMI indexes and writes to -o" do
    with_cli_reference do |ref, query, _|
      File.tempfile("minimap2-cli-index", ".mmi") do |index|
        cli(["-d", index.path, ref])[0].should eq(0)
        File.open(index.path, &.read_string(4)).should eq("MMI\x02")
        expected = cli(["-c", ref, query])[1]
        File.tempfile("minimap2-cli-output", ".paf") do |output|
          status, stdout, error = cli(["-c", "-o", output.path, index.path, query])
          status.should eq(0)
          stdout.should be_empty
          error.should be_empty
          File.read(output.path).should eq(expected)
        end
      end
    end
  end

  it "rejects output paths that alias input paths without truncating them" do
    with_cli_reference do |ref, query, _|
      original = File.read(ref)
      ["-o", "-d"].each do |option|
        cli([option, ref, ref, query])[0].should eq(1)
        File.read(ref).should eq(original)
      end
      cli(["-d", ref + "/missing.mmi", ref])[0].should eq(1)
      cli(["-x", "not-a-preset", ref, query])[0].should eq(1)
    end
  end

  it "distinguishes secondary alignments and suppresses their output when requested" do
    with_cli_reference do |ref, query, reference|
      File.write(ref, ">one\n#{reference}\n>two\n#{reference}\n")
      status, output, _ = cli(["-a", ref, query])
      status.should eq(0)
      records = output.lines.reject(&.starts_with?('@')).map(&.split('\t'))
      secondary = records.find { |record| (record[1].to_i & 256) != 0 }.should_not be_nil
      secondary[9, 2].should eq(["*", "*"])
      status, output, _ = cli(["-a", "--secondary=no", ref, query])
      status.should eq(0)
      output.lines.reject(&.starts_with?('@')).each do |line|
        (line.split('\t')[1].to_i & 256).should eq(0)
      end
    end
  end
end
