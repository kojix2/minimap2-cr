require "./spec_helper"
require "../examples/cli/command"

private def cli(args : Array(String)) : Tuple(Int32, String, String)
  output = IO::Memory.new
  error = IO::Memory.new
  status = Minimap2::CLI.run(args, output, error)
  {status, output.to_s, error.to_s}
end

# Optional differential checks against the pinned native minimap2 executable.
# MINIMAP2_BIN=./minimap2/minimap2 crystal spec
if binary = ENV["MINIMAP2_BIN"]?
  describe "native minimap2 compatibility" do
    %w[map-ont map-hifi sr splice asm5].each do |preset|
      [false, true].each do |sam|
        ["--cs", "--MD"].each do |tag|
          it "matches #{preset} #{sam ? "SAM" : "PAF"} #{tag} fields and tags" do
            with_cli_reference do |ref, query, reference|
              other = reference.reverse
              File.write(ref, ">one\n#{reference}\n>two\n#{other}\n>duplicate\n#{reference}\n")
              exact = reference[500, 1500]
              substitution = exact.to_slice.dup
              substitution[700] = substitution[700] == 'A'.ord ? 'C'.ord.to_u8 : 'A'.ord.to_u8
              reads = {
                "exact"         => exact,
                "reverse"       => Minimap2.revcomp(other[500, 1500]),
                "substitution"  => String.new(substitution),
                "indels"        => exact[0, 400] + "ACGTACG" + exact[400, 600] + exact[1007..],
                "clipped"       => "N" * 101 + other[500, 1500] + "N" * 57,
                "split"         => reference[500, 1500] + other[3000, 1500],
                "split_reverse" => Minimap2.revcomp(reference[500, 1500] + other[3000, 1500]),
                "unmapped"      => "N" * 500,
              }
              File.open(query, "w") do |file|
                reads.each do |name, sequence|
                  quality = String.build { |io| sequence.bytesize.times { |i| io << (33 + i % 50).chr } }
                  file.puts "@#{name}\n#{sequence}\n+\n#{quality}"
                end
              end
              args = ["-x", preset, sam ? "-a" : "-c", tag, ref, query]
              native = IO::Memory.new
              native_error = IO::Memory.new
              Process.run(binary, args, output: native, error: native_error).success?.should be_true
              status, output, error = cli(args)
              status.should eq(0)
              error.should be_empty
              # Auxiliary tags such as AS, SA, and cm are outside this example's scope.
              normalize = ->(text : String) do
                text.lines.reject { |line| sam && line.starts_with?('@') }.map do |line|
                  fields = line.split('\t')
                  size = sam ? 11 : 12
                  tags = fields[size..].select { |field| %w[NM cs MD cg].includes?(field.split(':').first) }
                  fields[0, size] + tags.sort
                end
              end
              normalize.call(output).should eq(normalize.call(native.to_s))
            end
          end
        end
      end
    end
  end
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

describe Minimap2::CLI::Reads do
  it "normalizes RNA bases like minimap2 for FASTA and FASTQ" do
    [">rna\nAuUGc\n", "@rna\nAuUGc\n+\n!!!!!\n"].each do |text|
      reads = [] of Minimap2::CLI::Read
      Minimap2::CLI::Reads.each_io(IO::Memory.new(text)) { |read| reads << read }
      reads.first.sequence.should eq("AtTGc")
    end
  end

  it "reads multiline FASTA with comments and CRLF" do
    reads = [] of Minimap2::CLI::Read
    input = IO::Memory.new("\n>one comment\r\nAC\r\nGT\r\n>two comment\r\nTGCA\r\n")
    Minimap2::CLI::Reads.each_io(input) { |read| reads << read }
    reads.should eq([
      Minimap2::CLI::Read.new("one", "ACGT"),
      Minimap2::CLI::Read.new("two", "TGCA"),
    ])
    input.closed?.should be_false
  end

  it "reads four-line FASTQ with comments, CRLF and header-like quality" do
    reads = [] of Minimap2::CLI::Read
    input = IO::Memory.new("\n@one comment\r\nACGT\r\n+one\r\n@@>>\r\n@two\r\nTGCA\r\n+\r\n!!!!\r\n")
    Minimap2::CLI::Reads.each_io(input) { |read| reads << read }
    reads.should eq([
      Minimap2::CLI::Read.new("one", "ACGT", "@@>>"),
      Minimap2::CLI::Read.new("two", "TGCA", "!!!!"),
    ])
    input.closed?.should be_false
  end

  it "reads gzip input by magic bytes rather than filename suffix" do
    File.tempfile("minimap2-fastx", ".data") do |file|
      Compress::Gzip::Writer.open(file) { |gzip| gzip << ">gzip\nACGT\n" }
      file.flush
      reads = [] of Minimap2::CLI::Read
      Minimap2::CLI::Reads.each(file.path) { |read| reads << read }
      reads.should eq([Minimap2::CLI::Read.new("gzip", "ACGT")])
    end
  end

  it "rejects malformed headers, missing separators and incorrect quality lengths" do
    ["ACGT\n", ">\nACGT\n", "@\nACGT\n+\n!!!!\n"].each do |text|
      expect_raises(ArgumentError) do
        Minimap2::CLI::Reads.each_io(IO::Memory.new(text)) { |_| }
      end
    end
    ["@read\nACGT\n", "@read\nACGT\n+\n!!\n", "@read\nACGT\n+\n!!!!!\n"].each do |text|
      expect_raises(::Fastx::InvalidFormatError) do
        Minimap2::CLI::Reads.each_io(IO::Memory.new(text)) { |_| }
      end
    end
  end

  it "reports wrapped FASTQ as unsupported by fastx.cr" do
    expect_raises(::Fastx::InvalidFormatError) do
      Minimap2::CLI::Reads.each_io(IO::Memory.new("@read\nAC\nGT\n+\n!!\n!!\n")) { |_| }
    end
  end

  it "preserves empty FASTA and FASTQ records" do
    reads = [] of Minimap2::CLI::Read
    [">empty\n", "@empty2\n\n+\n\n"].each do |text|
      Minimap2::CLI::Reads.each_io(IO::Memory.new(text)) { |read| reads << read }
    end
    reads.map(&.sequence).should eq(["", ""])
  end
end

describe Minimap2::CLI do
  it "accepts -o - as standard output" do
    with_cli_reference do |ref, query, _|
      status, output, error = cli(["-c", "-o", "-", ref, query])
      status.should eq(0)
      error.should be_empty
      output.should eq(cli(["-c", ref, query])[1])
    end
  end

  it "preserves inversion alignment types in PAF" do
    with_cli_reference do |ref, query, reference|
      sequence = reference[500, 1500] + Minimap2.revcomp(reference[2000, 500]) + reference[2500, 1500]
      File.write(query, ">inversion\n#{sequence}\n")
      status, output, error = cli(["-c", ref, query])
      status.should eq(0)
      error.should be_empty
      output.should contain("tp:A:I")
    end
  end

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

  it "writes valid missing SEQ and QUAL fields for empty FASTQ reads" do
    with_cli_reference do |ref, query, _|
      File.write(query, "@empty\n\n+\n\n")
      status, output, error = cli(["-a", ref, query])
      status.should eq(0)
      error.should be_empty
      output.lines.last.split('\t')[9, 2].should eq(["*", "*"])
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

  it "honors preset secondary defaults and explicit overrides" do
    with_cli_reference do |ref, query, reference|
      File.write(ref, ">one\n#{reference}\n>two\n#{reference}\n")
      status, output, _ = cli(["-x", "sr", ref, query])
      status.should eq(0)
      output.should_not contain("tp:A:S")
      status, output, _ = cli(["-x", "sr", "--secondary=yes", ref, query])
      status.should eq(0)
      output.should contain("tp:A:S")
    end
  end

  it "rejects multi-part mapping before writing a SAM header" do
    with_cli_reference do |ref, query, reference|
      File.write(ref, ">one\n#{reference}\n>two\n#{reference.reverse}\n")
      idxopt = Minimap2::LibMinimap2::MmIdxoptT.new
      mapopt = Minimap2::LibMinimap2::MmMapoptT.new
      Minimap2::LibMinimap2.mm_set_opt(Pointer(LibC::Char).null, pointerof(idxopt), pointerof(mapopt))
      idxopt.batch_size = 1000_u64
      idxopt.mini_batch_size = 1000_i64
      File.tempfile("minimap2-cli-multipart", ".mmi") do |index|
        aligner = Minimap2::Aligner.new(idxopt, mapopt, 1, ref, index.path)
        begin
          aligner.index_parts.should eq(2)
        ensure
          aligner.finalize
        end
        status, output, error = cli(["-a", index.path, query])
        status.should eq(1)
        output.should be_empty
        error.should contain("single-part indexes only")
      end
    end
  end
end
