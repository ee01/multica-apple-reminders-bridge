#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if grep -RInE --exclude-dir=.git --exclude-dir=.build --exclude='*.zip' 'mul_[A-Za-z0-9_-]{12,}' .; then
  echo "Potential Multica PAT found in repository files." >&2
  exit 1
fi

echo "No Multica PAT-like secrets found."
