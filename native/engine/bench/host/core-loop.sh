#!/bin/bash
# The core loop across two sessions and two pool users (run as root): the account's volume holds its source,
# DerivedData and Swift package caches at one path; session A builds cold, session B rebuilds after a change.
set -u
ACCT=nma-acct1; AV=/Volumes/$ACCT; SRC=$AV/src/IceCubesApp
E=/usr/local/nomac-test/engine/simulator-use-engine; SESSION=/usr/local/nomac-test/session.sh
now() { python3 -c 'import time;print(time.time())'; }
el() { python3 -c "print(round($(now) - $1, 1))"; }
as() { local u=$1; shift; launchctl asuser "$(id -u "$u")" sudo -u "$u" -H "$@"; }
container=$(diskutil info / | awk -F': *' '/APFS Container:/ {print $2}' | tr -d ' ')
mount_account() { # user
  if ! diskutil info "$ACCT" >/dev/null 2>&1; then diskutil apfs addVolume "$container" APFS "$ACCT" -quota 20g >/dev/null; echo "  account volume made"; fi
  mount | grep -q " $AV " || diskutil mount "$ACCT" >/dev/null
  local t=$(now); chown -R "$1":staff "$AV"; chmod 700 "$AV"; echo "  account volume mounted at $AV, owned by $1 in $(el $t) s ($(du -sh "$AV" 2>/dev/null | cut -f1), $(find "$AV" | wc -l | tr -d ' ') files)"
}
build() { # user label
  local t=$(now)
  as "$1" xcodebuild -project "$SRC/IceCubesApp.xcodeproj" -scheme IceCubesApp -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$AV/dd" -clonedSourcePackagesDirPath "$AV/spm" -packageCachePath "$AV/spmcache" CODE_SIGNING_ALLOWED=NO build > "/tmp/core-$2.log" 2>&1
  local rc=$? secs=$(el $t)
  echo "  build ($2): exit $rc in $secs s, $(grep -c '^SwiftCompile\|^CompileSwift ' /tmp/core-$2.log) Swift compile steps, $(grep -c '^CompileC ' /tmp/core-$2.log) C, $(grep -E '^\*\* BUILD' /tmp/core-$2.log | head -1)"
}
run_app() { # user udid set label
  local app=$(find "$AV/dd/Build/Products" -maxdepth 2 -name "*.app" -path "*iphonesimulator*" | head -1)
  local bundle=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Info.plist")
  local t=$(now); as "$1" xcrun simctl --set "$3" install "$2" "$app"; local ti=$(el $t)
  t=$(now); as "$1" xcrun simctl --set "$3" launch "$2" "$bundle" >/dev/null; local tl=$(el $t)
  t=$(now)
  local r=$(printf '%s\n' '{"op":"describe"}' '{"op":"settle","first_change_ms":0}' '{"op":"describe"}' '{"op":"describe"}' | as "$1" "$E" --udid "$2" --set "$3" | tail -3 | python3 -c '
import sys, json
for l in sys.stdin:
    a = json.loads(l)
    if a.get("tree"):
        root = a["tree"][0]; print(f"read {a.get(\"ms\")} ms: app {root.get(\"AXLabel\")!r}, {len(json.dumps(a[\"tree\"]))} bytes")')
  echo "  install $ti s ($(du -sh "$app" | cut -f1)), launch $tl s, then (engine): $(echo $r | tr '\n' ' ') [$(el $t) s]"
}
echo "== session A: nmsim1, cold"
out=$(bash $SESSION start nmsim1 a); echo "  $(echo "$out" | head -1)"; eval $(echo "$out" | grep ^UDID=); UA=$UDID; SA=$SET
mount_account nmsim1
t=$(now); mkdir -p "$AV/src"; rsync -a --delete --exclude .git ~rentamac/IceCubesApp/ "$SRC/"; chown -R nmsim1:staff "$AV/src"; echo "  source copied in $(el $t) s ($(du -sh "$SRC" | cut -f1))"
build nmsim1 cold
run_app nmsim1 "$UA" "$SA" a
diskutil unmount "$AV" >/dev/null && echo "  account volume unmounted"; bash $SESSION end nmsim1 a | sed 's/^/  /'
echo "== session B: nmsim2, the same account"
out=$(bash $SESSION start nmsim2 b); echo "  $(echo "$out" | head -1)"; eval $(echo "$out" | grep ^UDID=); UB=$UDID; SB=$SET
mount_account nmsim2
build nmsim2 nochange
f="$SRC/IceCubesApp/App/Tabs/ToolbarTab.swift"; echo "// change $(date +%s)" >> "$f"; chown nmsim2 "$f"
build nmsim2 onefile
run_app nmsim2 "$UB" "$SB" b
diskutil unmount "$AV" >/dev/null; bash $SESSION end nmsim2 b | sed 's/^/  /'
