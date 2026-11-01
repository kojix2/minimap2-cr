# minimap2-cr

[![Test](https://github.com/kojix2/minimap2-cr/actions/workflows/test.yml/badge.svg)](https://github.com/kojix2/minimap2-cr/actions/workflows/test.yml)
[![Lines of Code](https://img.shields.io/endpoint?url=https%3A%2F%2Ftokei.kojix2.net%2Fbadge%2Fgithub%2Fkojix2%2Fminimap2-cr%2Flines)](https://tokei.kojix2.net/github/kojix2/minimap2-cr)

Crystal >= 1.19.1 bindings for [minimap2](https://github.com/lh3/minimap2).
Build/load reference indexes and map sequences with coordinates, MAPQ and CIGAR.

## Installation

Requires a C compiler, make, curl, tar, bzip2 and zlib development headers.
On Ubuntu: `sudo apt-get install build-essential curl bzip2 zlib1g-dev`.
On macOS, install Xcode Command Line Tools. Windows requires MinGW/MSYS2 with
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
`cs:`, `md:` and `ds:` request alignment tags. `aligner.seq(name, start, stop)`
retrieves reference sequence; `Minimap2.revcomp(sequence)` reverse-complements it.
For presets and detailed options, use [AlignerBuilder](src/minimap2/builder.cr).

## Development

```sh
shards install
crystal spec
```

To rebuild native code in a local checkout: `crystal run ext/build.cr`.
License: [MIT](LICENSE).
