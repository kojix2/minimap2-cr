# Examples

The [minimap2-cr command](minimap2-cr.cr) demonstrates the Crystal API.
Run the commands below from the repository root.

## Command example

```sh
shards install
mkdir -p bin
crystal build examples/minimap2-cr.cr -o bin/minimap2-cr
bin/minimap2-cr -x map-ont reference.fa reads.fq.gz > mappings.paf
bin/minimap2-cr -ax map-ont --MD reference.fa reads.fq > mappings.sam
bin/minimap2-cr -d reference.mmi reference.fa
bin/minimap2-cr -c --cs reference.mmi reads.fa -o mappings.paf
cat reads.fq | bin/minimap2-cr -a reference.mmi -
```

This small example uses the Crystal API and
[fastx.cr](https://github.com/bio-cr/fastx.cr) for FASTA/FASTQ parsing. The latter
is a development dependency used by the example and specs. It accepts multiline
FASTA and conventional four-line FASTQ,
gzip-compressed query files (detected by their contents), multiple query files,
and plain FASTA/FASTQ on standard input. Reference input is handled by minimap2.
Wrapped FASTQ records are not supported by fastx.cr; normalize them to four-line
records before running this example.
PAF omits unmapped reads; SAM includes them. `--secondary=no` suppresses secondary
hits while retaining supplementary alignments. Use `--help` for supported options.

Reads are mapped independently and serially; `-t` controls index construction
only. Paired-end mapping, mapping against multi-part indexes, long cs tags, and
the complete set of minimap2 options and auxiliary SAM/PAF tags are not included.
All index parts are held in memory. MMI files are compatible with the pinned
native minimap2 version. SAM includes NM and optionally cs/MD tags, but no SA tag.

## Validation

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

## Verified fixes

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
