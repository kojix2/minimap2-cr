require "../src/minimap2"

# load or build index
ref_path = "#{__DIR__}/../ext/minimap2/test/MT-human.fa"
aligner = Minimap2::Aligner.builder.with_cigar.with_index(ref_path)

# read a subsequence from the reference
# positions are 0-based, end is exclusive
seq = String.build do |io|
  File.open(ref_path) do |fh|
    fh.each_line do |line|
      next if line.empty? || line.starts_with?(">")
      io << line.strip
    end
  end
end
subseq = seq[100, 100]

# mapping
hits = aligner.map(subseq, cs: true, md: true)

# show result
pp hits
