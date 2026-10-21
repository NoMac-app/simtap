#!/bin/bash
# Builds the clipboard helper for the iOS Simulator (both architectures) into vendor/axe, beside the engine.
# simulator-use runs it inside a phone (simctl spawn) when simctl pbcopy cannot: a macOS user with no screen
# session has no pasteboard server, and pbcopy crashes there.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p ../../vendor/axe
xcrun -sdk iphonesimulator clang -O2 -arch arm64 -arch x86_64 -mios-simulator-version-min=17.0 -fobjc-arc -framework UIKit main.m -o ../../vendor/axe/simulator-use-pbset
codesign -s - --force ../../vendor/axe/simulator-use-pbset
