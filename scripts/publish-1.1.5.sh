#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
git push origin main
gh release create v1.1.5 release/v1.1.5/MacIPTV-universal.zip release/v1.1.5/SHA256SUMS.txt --repo spacecdr/MacIPTV --target "$(git rev-parse HEAD)" --title 'MacIPTV 1.1.5 — Catalogo compatto e telecomando nelle info' --notes-file release/notes-v1.1.5.md --prerelease
