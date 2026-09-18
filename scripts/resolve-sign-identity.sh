#!/usr/bin/env bash
# Prints the codesign identity to use for local app builds.
# Warnings go to stderr. Override with SIGN_IDENTITY or SKIP_CODESIGN=1.
set -euo pipefail

if [[ "${SKIP_CODESIGN:-}" == "1" ]]; then
  echo "skip"
  exit 0
fi

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "$SIGN_IDENTITY"
  exit 0
fi

first_identity_matching() {
  local pattern="$1"
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' -v pattern="$pattern" '$2 ~ pattern { print $2; exit }'
}

identity="$(first_identity_matching '^Apple Development:')"
if [[ -n "$identity" ]]; then
  echo "$identity"
  exit 0
fi

identity="$(first_identity_matching '^Developer ID Application:')"
if [[ -n "$identity" ]]; then
  echo "$identity"
  exit 0
fi

echo "-"
