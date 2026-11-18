# minimap2-cr

[![Test](https://github.com/kojix2/minimap2-cr/actions/workflows/test.yml/badge.svg)](https://github.com/kojix2/minimap2-cr/actions/workflows/test.yml)
[![Lines of Code](https://img.shields.io/endpoint?url=https%3A%2F%2Ftokei.kojix2.net%2Fbadge%2Fgithub%2Fkojix2%2Fminimap2-cr%2Flines)](https://tokei.kojix2.net/github/kojix2/minimap2-cr)

Crystal >= 1.19.1 bindings for [minimap2](https://github.com/lh3/minimap2).
Build/load reference indexes and map sequences with coordinates, MAPQ and CIGAR.

## Installation

Requires a C compiler, make, curl, tar, bzip2 and zlib development headers.
On Ubuntu: `sudo apt-get install build-essential curl bzip2 zlib1g-dev`.
On macOS, install Xcode Command Line Tools. Windows requires MSYS2 UCRT64 with
`MAKE=mingw32-make`; see [CI setup](.github/workflows/test.yml) for packages.

```yaml
dependencies:
  minimap2:
    github: kojix2/minimap2-cr
```

Run `shards install`. The postinstall hook builds the minimap2 version pinned in
[ext/build.cr](ext/build.cr). Crystal links `ext/libminimap2.a` statically;
setting a shared-library search path is not required.

## Map

```crystal
require "minimap2"

aligner = Minimap2::Aligner.new("reference.fa", preset: "map-ont", cigar: true)
hits = aligner.map("ACGTACGTACGT", cs: true, md: true)
hits.each { |hit| puts "#{hit.target_name}:#{hit.target_start} MAPQ=#{hit.mapq}" }
```

Supply your own FASTA or minimap2 index. Coordinates are zero-based and half-open.
`cs:`, `md:` and `ds:` request alignment tags and enable CIGAR generation for
that call. CIGAR and tags require an index containing reference sequences.
`Mapping#nm` is the edit distance when base-level alignment is performed
(`with_cigar`, `cigar: true`, or a tag request). Otherwise it is `nil`, rather
than zero. Code that uses `nm` must handle this missing value.
`aligner.seq(name, start, stop)` retrieves reference sequence, returning `nil`
for invalid ranges, missing contigs, or indexes built with `--idx-no-seq`.
`Minimap2.revcomp(sequence)` reverse-complements a sequence.
For presets and detailed options, use [AlignerBuilder](src/minimap2/builder.cr).

## Development

### Example command

```sh
crystal build examples/minimap2-cr.cr -o bin/minimap2-cr
bin/minimap2-cr -x map-ont reference.fa reads.fq.gz > mappings.paf
bin/minimap2-cr -ax map-ont --MD reference.fa reads.fq > mappings.sam
bin/minimap2-cr -d reference.mmi reference.fa
bin/minimap2-cr -c --cs reference.mmi reads.fa -o mappings.paf
cat reads.fq | bin/minimap2-cr -a reference.mmi -
```

This small example uses the Crystal API. It accepts multiline FASTA/FASTQ,
gzip-compressed query files (detected by their contents), multiple query files,
and plain FASTA/FASTQ on standard input. Reference input is handled by minimap2.
PAF omits unmapped reads; SAM includes them. `--secondary=no` suppresses secondary
hits while retaining supplementary alignments. Use `--help` for supported options.

Reads are mapped independently and serially; `-t` controls index construction
only. Paired-end mapping, mapping against multi-part indexes, long cs tags, and
the complete set of minimap2 options and auxiliary SAM/PAF tags are not included.
All index parts are held in memory. MMI files are compatible with the pinned
native minimap2 version. SAM includes NM and optionally cs/MD tags, but no SA tag.

### Checks

```sh
shards install
crystal spec
```

To rebuild native code in a local checkout: `crystal run ext/build.cr`.
License: [MIT](LICENSE).
