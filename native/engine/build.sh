#!/bin/bash
# Builds the engine against the FBSimulatorControl frameworks in vendor/axe (from AXe's release) and idb's
# private headers (compile time only; never shipped). IDB_HEADERS: a checkout of github.com/cameroncooke/idb
# at the commit AXe pins (scripts/build.sh in AXe), PrivateHeaders folder.
set -euo pipefail
cd "$(dirname "$0")"
P=${IDB_HEADERS:?set IDB_HEADERS to idb/PrivateHeaders}
F=../../vendor/axe/Frameworks
args=()
for d in AccessibilityPlatformTranslation AXRuntime CoreSimDeviceIO CoreSimulator CoreSimulatorUtilities SimulatorKit; do args+=(-I "$P/$d"); done
swiftc -O -swift-version 5 main.swift TextToHIDEvents.swift KeyCode.swift Support.swift -F "$F" -I "$P" "${args[@]}" \
  -framework FBControlCore -framework FBSimulatorControl -Xlinker -rpath -Xlinker @executable_path/Frameworks -target arm64-apple-macos14 -o simulator-use-engine
