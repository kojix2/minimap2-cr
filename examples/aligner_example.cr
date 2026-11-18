require "../src/minimap2"

# load or build index
ref_path = "#{__DIR__}/../ext/minimap2/test/MT-human.fa"
aligner = Minimap2::Aligner.build.with_cigar.with_index(ref_path)

# read a subsequence from the reference
# positions are 0-based, end is exclusive
subseq = aligner.seq("MT_human", 100, 200)

# mapping
hits = aligner.map(subseq, cs: true, md: true) if subseq

# show result
hits.try &.each do |hit|
  puts "#{hit.target_name}:#{hit.target_start}-#{hit.target_end} #{hit.strand} MAPQ=#{hit.mapq} CIGAR=#{hit.cigar_str}"
end
