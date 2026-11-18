require "option_parser"
require "./formatter"

module Minimap2Example
  class CLI
    @preset : String? = nil
    @sam = false
    @cigar = false
    @cs = false
    @md = false
    @eqx = false
    @secondary = true
    @threads = 1
    @dump : String? = nil
    @output : String? = nil
    @help = false
    @version = false

    def self.run(args : Array(String), output : IO = STDOUT, error : IO = STDERR) : Int32
      new.run(args.dup, output, error)
    end

    def run(args : Array(String), output : IO, error : IO) : Int32
      parser = options
      parser.parse(args)
      if @help || @version
        output.puts(@version ? Minimap2::VERSION : parser)
        return 0
      end
      validate_inputs(args)
      validate_outputs(args)
      aligner = build_aligner(args.first)
      begin
        if args.size > 1
          raise ArgumentError.new("This example supports mapping against single-part indexes only") if aligner.index_parts > 1
          if path = @output
            File.open(path, "w") { |file| map(aligner, args[1..], file) }
          else
            map(aligner, args[1..], output)
          end
        end
      ensure
        aligner.finalize
      end
      0
    rescue ex : Exception
      error.puts "minimap2-cr: #{ex.message}"
      1
    end

    private def validate_inputs(args : Array(String))
      raise ArgumentError.new("Expected a reference and queries (or -d FILE to build an index)") if args.empty? || (args.size == 1 && !@dump)
      raise ArgumentError.new("-t must be positive") unless @threads > 0
      raise ArgumentError.new("Standard input can only be used once") if args.count("-") > 1
    end

    private def build_aligner(reference : String) : Minimap2::Aligner
      builder = Minimap2::Aligner.build.with_index_threads(@threads)
      if preset = @preset
        builder.preset(preset)
      end
      builder.with_cigar if @sam || @cigar || @eqx
      # The native index reader silently ignores fopen failures for output.
      if dump = @dump
        File.open(dump, "w") { }
      end
      builder.with_index(reference, @dump)
    end

    private def options : OptionParser
      OptionParser.new do |parser|
        parser.banner = "Usage: minimap2-cr [options] <reference.fa|reference.mmi> [query.fa|query.fq ...]\nQueries may be gzip-compressed or '-' for standard input. Reads are mapped independently."
        parser.on("-x PRESET", "--preset PRESET", "minimap2 preset (map-ont, map-hifi, sr, splice, asm5, ...)") { |value| @preset = value }
        parser.on("-a", "Output SAM (default: PAF)") { @sam = true }
        parser.on("-c", "Include CIGAR in PAF") { @cigar = true }
        parser.on("--cs", "Include short cs tags") { @cs = true }
        parser.on("--MD", "Include MD tags") { @md = true }
        parser.on("--eqx", "Use =/X CIGAR operations (implies alignment)") { @eqx = true }
        parser.on("--secondary=BOOL", "Print secondary hits: yes or no [yes]") do |value|
          raise ArgumentError.new("--secondary must be yes or no") unless {"yes", "no"}.includes?(value)
          @secondary = value == "yes"
        end
        parser.on("-t INT", "Index construction threads; queries are mapped serially [1]") { |value| @threads = value.to_i }
        parser.on("-d FILE", "Save index; omit queries to build only") { |value| @dump = value }
        parser.on("-o FILE", "Write mappings to FILE [stdout]") { |value| @output = value }
        parser.on("-h", "--help", "Show help") { @help = true }
        parser.on("--version", "Show minimap2-cr version") { @version = true }
      end
    end

    private def validate_outputs(inputs : Array(String))
      paths = inputs.reject { |path| path == "-" }
      destinations = [@dump, @output].compact
      destinations.each_with_index do |destination, i|
        raise ArgumentError.new("Output must be a file path, not '-'") if destination == "-"
        (paths + destinations[0...i]).each do |path|
          if File.expand_path(path) == File.expand_path(destination) || (File.exists?(destination) && File.exists?(path) && File.same?(path, destination))
            raise ArgumentError.new("Output path would overwrite an input or another output: #{destination}")
          end
        end
      end
    end

    private def map(aligner : Minimap2::Aligner, paths : Array(String), output : IO)
      Formatter.sam_header(output, aligner.references) if @sam
      flags = @eqx ? [Minimap2::LibMinimap2::EQX.to_u64] : nil
      paths.each do |path|
        Fastx.each(path) do |read|
          hits = read.sequence.empty? ? [] of Minimap2::Mapping : aligner.map(read.sequence, cs: @cs, md: @md, extra_flags: flags, query_name: read.name)
          hits.reject!(&.secondary?) unless @secondary
          if @sam
            if hits.empty?
              Formatter.sam(output, read, nil)
            else
              hits.each { |hit| Formatter.sam(output, read, hit) }
            end
          else
            hits.each { |hit| Formatter.paf(output, read, hit, @cigar) }
          end
        end
      end
    end
  end
end
