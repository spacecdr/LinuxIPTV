#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
git push origin main
gh release create v1.1.0 release/v1.1.0/MacIPTV-universal.zip release/v1.1.0/SHA256SUMS.txt --repo spacecdr/MacIPTV --target "$(git rev-parse HEAD)" --title 'MacIPTV 1.1.0 — Playlist, EPG e nuove finestre' --notes-file release/notes-v1.1.0.md --prerelease
