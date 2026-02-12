# minimap2-cr

[![CI](https://github.com/kojix2/minimap2-cr/actions/workflows/test.yml/badge.svg)](https://github.com/kojix2/minimap2-cr/actions/workflows/test.yml)

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

### `new` (shortcut)

`new` accepts keyword options for common settings.

```crystal
require "minimap2"

aligner = Minimap2::Aligner.new("reference.fasta", preset: "map-ont", cigar: true, threads: 4)
hits = aligner.map("ACGTACGTACGT")
puts hits.size
```

### `new` with block

`new` applies keyword options first, then yields the builder for extra configuration.

```crystal
require "minimap2"

aligner = Minimap2::Aligner.new("reference.fasta") do |b|
  b.map_ont
  b.with_cigar
  b.with_index_threads(4)
end
```

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

## Contributing

1. Fork it (<https://github.com/your-github-user/minimap2/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [kojix2](https://github.com/your-github-user) - creator and maintainer
