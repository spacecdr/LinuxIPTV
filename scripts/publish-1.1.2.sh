#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
git push origin main
gh release create v1.1.2 release/v1.1.2/MacIPTV-universal.zip release/v1.1.2/SHA256SUMS.txt --repo spacecdr/MacIPTV --target "$(git rev-parse HEAD)" --title 'MacIPTV 1.1.2 — Associazione EPG automatica' --notes-file release/notes-v1.1.2.md --prerelease
