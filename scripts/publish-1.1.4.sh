#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
git push origin main
gh release create v1.1.4 release/v1.1.4/MacIPTV-universal.zip release/v1.1.4/SHA256SUMS.txt --repo spacecdr/MacIPTV --target "$(git rev-parse HEAD)" --title 'MacIPTV 1.1.4 — Correzione crash fullscreen' --notes-file release/notes-v1.1.4.md --prerelease
