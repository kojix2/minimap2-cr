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
mkdir -p bin
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
ameba src spec examples
crystal tool format --check src spec examples
```

If a matching native minimap2 executable is available, enable the additional
compatibility specs (the reference clone used here is minimap2 v2.31):

```sh
MINIMAP2_BIN=./minimap2/minimap2 crystal spec
```

These compare five presets (`map-ont`, `map-hifi`, `sr`, `splice`, `asm5`) in both
PAF and SAM, with cs and MD checked individually. They exercise exact matches,
substitutions, insertions/deletions, reverse strands, clipping, split alignments,
secondary hits, and unmapped reads. Comparison covers mandatory fields and the
supported NM/cg/cs/MD tags, rather than minimap2's complete auxiliary tag set.

### Verified fixes

The existing API issues below were reproduced against commit `598ad08` before
fixing them. The CLI issues were caught while checking the new example. Each has
a regression spec that fails before the corresponding fix and passes afterward.

| Area | Bug and observed evidence | Fix and verification |
| --- | --- | --- |
| Existing `idx_seq` helper | Creating an index terminated the process abnormally: GC-allocated pointer arrays were passed to `LibC.free`. | Use stack pointer slots. Repeatedly build, retrieve the indexed sequence, and destroy the native index. |
| Existing index output | An unwritable output such as `reference.fa/missing.mmi` returned an aligner successfully, without creating an index file. The native reader ignores output `fopen` failures. | Check the output can be opened and propagate `File::Error`; tested with an invalid destination. |
| Existing index output | Using the reference path as index output silently replaced the FASTA contents with a file beginning with `MMI\x02`. | Reject paths identifying the reference, including file aliases, before opening output. The spec verifies an exception and unchanged reference contents. |
| New CLI preset handling | `-x sr` printed secondary hits despite the preset's `NO_PRINT_2ND` flag; comparison against native minimap2 exposed the extra records. | Use the preset's default unless `--secondary=yes/no` is explicit. Check both the default and explicit override, plus native comparisons. |
| New CLI empty FASTQ output | An empty read produced an empty SAM QUAL field instead of the missing-value marker. | Emit `*` for empty sequence/quality fields; verify the exact SAM fields. The [SAM specification](https://samtools.github.io/hts-specs/SAMv1.pdf) requires QUAL to be `*` or one or more printable quality characters. |

Local validation on macOS also checked SAM conversion with `samtools view`, plain
stdin, gzip query files, `--eqx`, and MMI exchange in both directions with native
minimap2. These checks establish the tested behaviors; they do not claim parity
for every minimap2 feature or preset.

To rebuild native code in a local checkout: `crystal run ext/build.cr`.
License: [MIT](LICENSE).
