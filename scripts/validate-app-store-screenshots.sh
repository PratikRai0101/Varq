#!/bin/bash
set -euo pipefail

screenshot_directory="${1:-docs/app-store/screenshots}"
expected_width=2880
expected_height=1800
expected_files=(
  "01-library.png"
  "02-reader.png"
  "03-highlights-notes.png"
  "04-comics.png"
  "05-private-shelf.png"
  "06-settings.png"
)

failures=0

for filename in "${expected_files[@]}"; do
  filepath="${screenshot_directory}/${filename}"

  if [[ ! -f "${filepath}" ]]; then
    echo "Missing screenshot: ${filepath}" >&2
    failures=1
    continue
  fi

  metadata="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "${filepath}")"
  width="$(awk -F ': ' '/pixelWidth/ { print $2 }' <<<"${metadata}")"
  height="$(awk -F ': ' '/pixelHeight/ { print $2 }' <<<"${metadata}")"
  has_alpha="$(awk -F ': ' '/hasAlpha/ { print $2 }' <<<"${metadata}")"

  if [[ "${width}" != "${expected_width}" || "${height}" != "${expected_height}" ]]; then
    echo "Invalid dimensions for ${filepath}: expected ${expected_width}x${expected_height}, found ${width}x${height}" >&2
    failures=1
  fi

  if [[ "${has_alpha}" != "no" ]]; then
    echo "Screenshot must not contain an alpha channel: ${filepath}" >&2
    failures=1
  fi
done

if [[ "${failures}" -ne 0 ]]; then
  exit 1
fi

echo "Validated ${#expected_files[@]} App Store screenshots in ${screenshot_directory}."
