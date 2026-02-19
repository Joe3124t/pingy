#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install: brew install xcodegen"
  exit 1
fi

xcodegen generate --spec project.yml
echo "Generated Xcode project at $ROOT_DIR/Pingy.xcodeproj"
