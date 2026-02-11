# minimap2

TODO: Write a description here

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     minimap2:
       github: your-github-user/minimap2
   ```

2. Run `shards install`

## Usage

```crystal
require "minimap2"

aligner = Minimap2::Aligner.builder
  .map_ont
  .with_cigar
  .with_index("reference.fasta")

hits = aligner.map("ACGTACGTACGT")
puts hits.size
```

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/your-github-user/minimap2/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [kojix2](https://github.com/your-github-user) - creator and maintainer
