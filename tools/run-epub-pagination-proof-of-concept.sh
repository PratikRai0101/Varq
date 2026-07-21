#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
binary_path=$(mktemp -d)/epub-pagination-proof
trap 'rm -f "$binary_path"; rmdir "$(dirname "$binary_path")"' EXIT

xcrun swiftc \
  -parse-as-library \
  -framework AppKit \
  -framework WebKit \
  "$root_dir/tools/EpubPaginationProofOfConcept.swift" \
  -o "$binary_path"

"$binary_path" "$root_dir/VarqTests/Fixtures/pagination.epub"
