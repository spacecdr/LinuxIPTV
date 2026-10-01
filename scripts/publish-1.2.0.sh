#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
git push origin main
gh release create v1.2.0 release/v1.2.0/MacIPTV-universal.zip release/v1.2.0/SHA256SUMS.txt --repo spacecdr/MacIPTV --target "$(git rev-parse HEAD)" --title 'MacIPTV 1.2.0 — Stabile' --notes-file release/notes-v1.2.0.md --latest
