#!/usr/bin/env bash
# Moves the Swift sources from apple/Sources/ into the Xcode project you created
# (apple/CPRCoach/), replacing Xcode's template App/ContentView files.
# Xcode's folder-synchronized groups pick the files up automatically.
set -euo pipefail
cd "$(dirname "$0")"

PROJ=CPRCoach
IOS_DIR="$PROJ/CPRCoach"
WATCH_DIR="$(find "$PROJ" -maxdepth 1 -type d -name '*Watch App' 2>/dev/null | head -1 || true)"

if [[ ! -d "$PROJ/CPRCoach.xcodeproj" || ! -d "$IOS_DIR" || -z "$WATCH_DIR" ]]; then
  echo "Couldn't find the Xcode project. Expected:"
  echo "  apple/CPRCoach/CPRCoach.xcodeproj"
  echo "  apple/CPRCoach/CPRCoach/"
  echo "  apple/CPRCoach/CPRCoach Watch App/"
  echo "Create it first (apple/SETUP.md, step 1)."
  exit 1
fi

move() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git ls-files --error-unmatch "$1" >/dev/null 2>&1; then
    git mv -f "$1" "$2"
  else
    mv -f "$1" "$2"
  fi
}

echo "Removing template files…"
rm -f "$IOS_DIR/ContentView.swift" "$IOS_DIR"/*App.swift
rm -f "$WATCH_DIR/ContentView.swift" "$WATCH_DIR"/*App.swift

echo "Installing iOS sources → $IOS_DIR"
for f in Sources/iOS/*.swift; do move "$f" "$IOS_DIR/"; done
echo "Installing watch sources → $WATCH_DIR"
for f in Sources/Watch/*.swift; do move "$f" "$WATCH_DIR/"; done
rmdir Sources/iOS Sources/Watch Sources 2>/dev/null || true

echo "Done. In Xcode, the files should appear under each target automatically."
echo "If they don't (older non-synchronized project), drag them into the matching group and tick only that target."
