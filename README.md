# minimap2-cr

[![CI](https://github.com/kojix2/minimap2-cr/actions/workflows/test.yml/badge.svg)](https://github.com/kojix2/minimap2-cr/actions/workflows/test.yml)
[![Lines of Code](https://img.shields.io/endpoint?url=https%3A%2F%2Ftokei.kojix2.net%2Fbadge%2Fgithub%2Fkojix2%2Fminimap2-cr%2Flines)](https://tokei.kojix2.net/github/kojix2/minimap2-cr)

Crystal bindings for [minimap2](https://github.com/lh3/minimap2) (long-read mapper).

This shard downloads/builds minimap2 during install (see `shard.yml` `postinstall`).

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     minimap2:
       github: kojix2/minimap2-cr
   ```

2. Run `shards install`

### System requirements (Linux)

Building minimap2 requires a C toolchain and zlib headers.

```sh
sudo apt-get update
sudo apt-get install -y build-essential curl bzip2 zlib1g-dev
```

## Usage

### Quick Start

```crystal
require "minimap2"

aligner = Minimap2::Aligner.new(
  "reference.fasta",
  preset: "map-ont",
  cigar: true,
  threads: 4
)

hits = aligner.map("ACGTACGTACGT", cs: true, md: true, ds: true)
pp hits.first?
```

### Builder Style (recommended for explicit config)

```crystal
require "minimap2"

aligner = Minimap2::Aligner.build
  .map_hifi
  .with_cigar
  .with_index_threads(4)
  .with_index("reference.fasta")
```

Available builder presets:

- `map_ont`
- `map_hifi`
- `map_pb`
- `splice`
- `splice_hq`
- `splice_sr`
- `asm5`
- `asm10`
- `asm20`
- `sr`

### Practical Mapping Options

`map` supports these high-level toggles:

- `cs: true`: emit `cs` tag text
- `md: true`: emit `MD` tag text
- `ds: true`: emit `ds` tag text (INDEL uncertainty extension)

Returned fields are available on `Minimap2::Mapping` as `cs`, `md`, and `ds`.

You can also pass minimap2 flags directly via `extra_flags`:

```crystal
hits = aligner.map(
  query,
  extra_flags: [
    Minimap2::LibMinimap2::OUT_MD.to_u64,
    Minimap2::LibMinimap2::EQX.to_u64,
  ]
)
```

### API Notes

- `Aligner.new(...)` is a shortcut wrapper around the builder.
- `Aligner.build` gives full control and is preferred for non-trivial setups.
- `Aligner#seq(name, start, stop)` reads reference subsequences from the loaded index.

## Upstream minimap2 references

- Presets and command behavior: https://github.com/lh3/minimap2#readme
- CLI/manpage options (`--cs`, `--MD`, `--ds`): https://github.com/lh3/minimap2/blob/master/minimap2.1
- `ds` tag background (release note): https://github.com/lh3/minimap2/blob/master/NEWS.md

### Utilities

```crystal
require "minimap2"

puts Minimap2.revcomp("ACGTN")
```

## Development

- Build vendored minimap2: `shards install` (runs `ext/build.cr` via postinstall)
- Run tests: `crystal spec`

If you see runtime linker errors, try:

```sh
export LD_LIBRARY_PATH="$PWD/ext"
```
