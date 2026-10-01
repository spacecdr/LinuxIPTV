#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
git push origin main
gh release create v1.1.3 release/v1.1.3/MacIPTV-universal.zip release/v1.1.3/SHA256SUMS.txt --repo spacecdr/MacIPTV --target "$(git rev-parse HEAD)" --title 'MacIPTV 1.1.3 — Comandi e catalogo compatto' --notes-file release/notes-v1.1.3.md --prerelease
