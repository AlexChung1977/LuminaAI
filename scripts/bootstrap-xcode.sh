#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/Apps/MediaShelf"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
  echo "Generated Apps/MediaShelf/MediaShelf.xcodeproj"
  echo "Open with: open Apps/MediaShelf/MediaShelf.xcodeproj"
else
  cat <<'EOF'
XcodeGen is not installed.

Option A (recommended):
  brew install xcodegen
  ./scripts/bootstrap-xcode.sh

Option B:
  1. Xcode → File → New → Project → Multiplatform App (SwiftUI)
  2. Product Name: MediaShelf
  3. File → Add Package Dependencies → Add Local → select repo root
  4. Add MediaShelfCore to the app target
  5. Replace the template sources with Apps/MediaShelf/MediaShelf/*
EOF
fi
