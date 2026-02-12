require "file_utils"
require "random/secure"

TAG     = "v2.30"
VERSION = TAG.lchop('v')
TARBALL = "minimap2-#{VERSION}.tar.bz2"
URL     = "https://github.com/lh3/minimap2/releases/download/#{TAG}/#{TARBALL}"

ROOT_DIR = File.expand_path("..", __DIR__)
EXT_DIR  = File.join(ROOT_DIR, "ext")
SRC_DIR  = File.join(EXT_DIR, "minimap2")

LIB_A_SRC = File.join(SRC_DIR, "libminimap2.a")
LIB_A_DST = File.join(EXT_DIR, "libminimap2.a")

{% if flag?(:darwin) %}
  OUT_LIB = File.join(EXT_DIR, "libminimap2.dylib")
{% elsif flag?(:windows) %}
  OUT_LIB = ""
{% else %}
  OUT_LIB = File.join(EXT_DIR, "libminimap2.so")
{% end %}

private def run!(cmd : String, args : Array(String), chdir : String? = nil)
  status = Process.run(cmd, args, chdir: chdir, input: Process::Redirect::Inherit, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
  raise "Command failed (#{status.exit_code}): #{cmd} #{args.join(" ")}" unless status.success?
end

private def ensure_minimap2_sources
  return if Dir.exists?(SRC_DIR)

  FileUtils.mkdir_p(EXT_DIR)

  tmp = File.join(Dir.tempdir, "minimap2-cr-#{Random::Secure.hex(8)}")
  FileUtils.mkdir_p(tmp)
  begin
    tar_path = File.join(tmp, TARBALL)

    puts "Downloading #{URL}"
    run!("curl", ["-fsSL", URL, "-o", tar_path])

    puts "Extracting #{TARBALL}"
    run!("tar", ["-xjf", tar_path, "-C", tmp])

    extracted = File.join(tmp, "minimap2-#{VERSION}")
    raise "Unexpected archive layout: #{TARBALL}" unless Dir.exists?(extracted)

    FileUtils.mv(extracted, SRC_DIR)
  ensure
    FileUtils.rm_rf(tmp) if Dir.exists?(tmp)
  end
end

private def build_static
  puts "Building libminimap2.a"

  make_args = ["-C", SRC_DIR, "libminimap2.a", "CFLAGS=-fPIC -O2 -Wall -Wc++-compat"]
  {% if flag?(:aarch64) %}
    make_args << "aarch64=1"
  {% end %}

  run!("make", make_args)
  FileUtils.cp(LIB_A_SRC, LIB_A_DST)
end

private def build_shared
  {% if flag?(:windows) %}
    # On Windows, prefer static linking (ext/libminimap2.a).
    puts "Windows: static lib installed at #{LIB_A_DST}"
  {% elsif flag?(:darwin) %}
    puts "Linking #{OUT_LIB}"
    run!("cc", [
      "-dynamiclib",
      "-o", OUT_LIB,
      "-Wl,-install_name,@rpath/libminimap2.dylib",
      "-Wl,-force_load,#{LIB_A_SRC}",
      "-lm", "-lz", "-lpthread",
    ])
  {% else %}
    puts "Linking #{OUT_LIB}"
    run!("cc", [
      "-shared",
      "-o", OUT_LIB,
      "-Wl,--whole-archive", LIB_A_SRC, "-Wl,--no-whole-archive",
      "-lm", "-lz", "-lpthread",
    ])
  {% end %}
end

ensure_minimap2_sources
build_static
build_shared
