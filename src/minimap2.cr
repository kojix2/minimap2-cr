require "./minimap2/ffi"
require "./minimap2/types"
require "./minimap2/builder"
require "./minimap2/aligner"
require "./minimap2/mappy"

module Minimap2
  VERSION = {{ `shards version #{__DIR__}`.chomp.stringify }}
end
