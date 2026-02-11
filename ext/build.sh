#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXT_DIR="$ROOT_DIR/ext"
SRC_DIR="$EXT_DIR/minimap2"
OUT_LIB="$EXT_DIR/libminimap2.so"

if [[ ! -d "$SRC_DIR" ]]; then
  mkdir -p "$EXT_DIR"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  tag="$(curl -fsSL https://api.github.com/repos/lh3/minimap2/releases/latest | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"\s*:\s*"([^"]+)".*/\1/')"
  if [[ -z "$tag" ]]; then
    echo "Failed to determine latest minimap2 tag." >&2
    exit 1
  fi

  version="${tag#v}"
  tarball="minimap2-${version}.tar.bz2"
  url="https://github.com/lh3/minimap2/releases/download/${tag}/${tarball}"

  curl -fsSL "$url" -o "$tmpdir/$tarball"
  tar -xjf "$tmpdir/$tarball" -C "$tmpdir"

  if [[ ! -d "$tmpdir/minimap2-${version}" ]]; then
    echo "Unexpected archive layout for $tarball." >&2
    exit 1
  fi

  mv "$tmpdir/minimap2-${version}" "$SRC_DIR"
fi

make -C "$SRC_DIR" libminimap2.a CFLAGS="-fPIC -O2 -Wall -Wc++-compat"

cc -shared -o "$OUT_LIB" \
  -Wl,--whole-archive "$SRC_DIR/libminimap2.a" -Wl,--no-whole-archive \
  -lm -lz -lpthread
