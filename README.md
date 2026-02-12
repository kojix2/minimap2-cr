# minimap2-cr

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

### Basic mapping

```crystal
require "minimap2"

aligner = Minimap2::Aligner.build
  .map_ont
  .with_cigar
  .with_index("reference.fasta")

hits = aligner.map("ACGTACGTACGT")
puts hits.size
```

### Ruby-minimap2-like quick start

This mirrors ruby-minimap2's `Aligner#seq` + mapping flow.

```crystal
require "minimap2"

ref_path = "#{__DIR__}/ext/minimap2/test/MT-human.fa"

aligner = Minimap2::Aligner.new(ref_path, cigar: true)
seq     = aligner.seq("MT_human", 100, 200)
raise "seq not found" unless seq

hits = aligner.map(seq, cs: true, md: true)
pp hits
```

### Block-style `new`

`new` can take keyword options and a block; keyword options are applied first.

```crystal
require "minimap2"

aligner = Minimap2::Aligner.new("reference.fasta", preset: "map-ont", cigar: true) do |b|
  b.with_index_threads(4)
end
```

### Utilities

```crystal
require "minimap2"

puts Minimap2.revcomp("ACGTN")
```

## Development

- Build vendored minimap2: `shards install` (runs `ext/build.sh` via postinstall)
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
