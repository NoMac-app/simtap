#!/bin/bash
# E3b (root): the pool user's home on the session volume, arm64 only, Spotlight off, full cleanup at the end,
# no-change and one-file builds, touch-all, relocation, simctl install against an rsync into the app's container.
set -u
ACCT=nma-acct1; AV=/Volumes/$ACCT; SRC=$AV/src/IceCubesApp
E=/usr/local/nomac-test/engine/simulator-use-engine; GOLDEN=/Library/NoMacSim/golden/current
now() { python3 -c 'import time;print(time.time())'; }
el() { python3 -c "print(round($(now) - $1, 1))"; }
as() { local u=$1; shift; launchctl asuser "$(id -u "$u")" sudo -u "$u" -H "$@"; }
container=$(diskutil info / | awk -F': *' '/APFS Container:/ {print $2}' | tr -d ' ')
start() { # user session -> UDID: the session volume mounted at ~/Library/Developer (phones, DerivedData, simulator caches)
  local u=$1 s=$2 t=$(now) vol=nms-$2 H=/Users/$1
  diskutil apfs addVolume "$container" APFS "$vol" -quota 20g -nomount >/dev/null
  mkdir -p "$H/Library/Developer"; chown "$u":staff "$H/Library" "$H/Library/Developer"
  diskutil mount -mountPoint "$H/Library/Developer" "$vol" >/dev/null; mdutil -i off "$H/Library/Developer" >/dev/null 2>&1
  local D=$H/Library/Developer/CoreSimulator/Devices; mkdir -p "$D"
  UDID=$(uuidgen); cp -R "$GOLDEN" "$D/$UDID"
  /usr/libexec/PlistBuddy -c "Set :UDID $UDID" -c "Set :name phone" "$D/$UDID/device.plist"
  chown -R "$u":staff "$H/Library/Developer" 2>/dev/null; chmod 700 "$H/Library/Developer"; local t1=$(now)
  as "$u" xcrun simctl boot "$UDID" && as "$u" perl -e 'alarm shift; exec @ARGV' 90 xcrun simctl bootstatus "$UDID" -b >/dev/null
  BOOT_OK=$?; [ $BOOT_OK = 0 ] || echo "  BOOT HUNG: bootstatus did not finish in 90 s ($(ls /Library/Logs/DiagnosticReports | grep -c notifyd) notifyd crash reports on the host)"
  echo "  session $s for $u: volume and phone $(python3 -c "print(round($t1-$t,1))") s, booted $(el $t1) s; simctl sees $(as "$u" xcrun simctl list devices booted | grep -c Booted) booted"
}
wipe_home() { # user: everything the user could have written, gone; prints what is left
  local u=$1 H=/Users/$1 uid=$(id -u "$1")
  for p in "$H"/* "$H"/.[!.]* "$H"/Library/* "$H"/Library/.[!.]*; do [ "$p" = "$H/Library" ] || rm -rf "$p" 2>/dev/null; done
  find /private/tmp /private/var/tmp /Users/Shared -user "$uid" -delete 2>/dev/null
  local tmp=$(sudo -u "$u" getconf DARWIN_USER_TEMP_DIR) cache=$(sudo -u "$u" getconf DARWIN_USER_CACHE_DIR)
  rm -rf "$tmp"* "$cache"* 2>/dev/null
  echo "$(find "$H" -mindepth 1 2>/dev/null | wc -l | tr -d ' ') entries left in the home ($(find "$H" -mindepth 1 -type f 2>/dev/null | wc -l | tr -d ' ') files)"
}
finish() { # user session
  local u=$1 s=$2 uid=$(id -u "$1") t=$(now)
  as "$u" xcrun simctl shutdown all >/dev/null 2>&1
  launchctl bootout "user/$uid" 2>/dev/null; local b=$?
  for i in 1 2 3 4 5 6; do pkill -9 -u "$uid" 2>/dev/null; sleep 0.5; pgrep -u "$uid" >/dev/null || break; done
  local left=$(pgrep -u "$uid" | wc -l | tr -d ' ')
  mount | grep -q " $AV " && { diskutil unmount "$AV" >/dev/null 2>&1 || diskutil unmount force "$AV" >/dev/null; }
  local dev=$(diskutil list | awk -v v="nms-$s" '$0 ~ " "v" " {print $NF}' | head -1)
  diskutil apfs deleteVolume "$dev" >/dev/null 2>&1 || diskutil apfs deleteVolume "$dev" -force >/dev/null 2>&1
  local w=$(wipe_home "$u")
  echo "  session $s ended in $(el $t) s: bootout exit $b, $left processes left after the kill, account volume $(mount | grep -q " $AV " && echo STILL MOUNTED || echo unmounted), session volume $(diskutil info "nms-$s" >/dev/null 2>&1 && echo STILL THERE || echo deleted), $w"
}
mount_account() { # user
  mount | grep -q " $AV " || diskutil mount "$ACCT" >/dev/null; mdutil -i off "$AV" >/dev/null 2>&1
  local t=$(now); chown -R "$1":staff "$AV" 2>/dev/null; chmod 700 "$AV"; echo "  account volume owned by $1 in $(el $t) s ($(du -sh "$AV" 2>/dev/null | cut -f1))"
}
FLAGS="-skipPackageUpdates -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipMacroValidation -skipPackagePluginValidation"
build() { # user label [extra xcodebuild args...]
  local u=$1 label=$2; shift 2; local t=$(now)
  as "$u" xcodebuild -project "$SRC/IceCubesApp.xcodeproj" -scheme IceCubesApp -destination "platform=iOS Simulator,id=$DEST" \
    -derivedDataPath "$AV/dd" -clonedSourcePackagesDirPath "$AV/spm" -packageCachePath "$AV/spmcache" $FLAGS \
    CODE_SIGNING_ALLOWED=NO -showBuildTimingSummary "$@" build > "/tmp/e3b-$label.log" 2>&1
  local rc=$? secs=$(el $t)
  echo "  build ($label): exit $rc in $secs s, $(grep -c '^SwiftCompile ' /tmp/e3b-$label.log) Swift compiles, $(grep -c '^CompileC ' /tmp/e3b-$label.log) C, $(grep -cE '^(Ld|Link) ' /tmp/e3b-$label.log) links, $(grep -E '^\*\* BUILD' /tmp/e3b-$label.log | head -1)"
}
APP() { find "$AV/dd/Build/Products" -maxdepth 2 -name "*.app" -path "*iphonesimulator*" | head -1; }
read_app() { # user udid -> engine reads the screen after a settle
  printf '%s\n' '{"op":"describe"}' '{"op":"settle","first_change_ms":0}' '{"op":"describe"}' | as "$1" "$E" --udid "$2" | python3 /tmp/read.py | tail -2 | tr '\n' ';'
}
install_launch() { # user udid label
  local app=$(APP) bundle; bundle=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Info.plist")
  local t=$(now); as "$1" xcrun simctl install "$2" "$app"; local ti=$(el $t)
  t=$(now); as "$1" xcrun simctl launch "$2" "$bundle" >/dev/null; local tl=$(el $t)
  t=$(now); local r=$(read_app "$1" "$2")
  echo "  $3: simctl install $ti s ($(du -sh "$app" | cut -f1)), launch $tl s, engine $r [$(el $t) s]"
}
quick_install() { # user udid label: rsync the new build into the installed app, then relaunch
  local app=$(APP) bundle; bundle=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Info.plist")
  local dest; dest=$(as "$1" xcrun simctl get_app_container "$2" "$bundle" app)
  local t=$(now); as "$1" xcrun simctl terminate "$2" "$bundle" >/dev/null 2>&1
  local n=$(as "$1" rsync -a --delete --checksum --itemize-changes "$app/" "$dest/" | grep -c '^>f'); local tr=$(el $t)
  t=$(now); as "$1" xcrun simctl launch "$2" "$bundle" >/dev/null; local tl=$(el $t)
  local same=$(cmp -s "$app/Ice Cubes.debug.dylib" "$dest/Ice Cubes.debug.dylib" && echo yes || echo NO)
  t=$(now); local r=$(read_app "$1" "$2")
  echo "  $3: rsync into the container $tr s ($n files changed, new code in place: $same), launch $tl s, engine $r [$(el $t) s]"
}
echo "== session A: nmsim1, cold arm64 build"
for u in 507 508; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
for v in nms-h1 nms-a nms-b; do d=$(diskutil list | awk -v v="$v" '$0 ~ " "v" " {print $NF}' | head -1); [ -n "$d" ] && diskutil apfs deleteVolume "$d" >/dev/null; done
echo "  before: nmsim1 $(wipe_home nmsim1); nmsim2 $(wipe_home nmsim2)"
start nmsim1 a; UA=$UDID; DEST=$UA
mount_account nmsim1
rm -rf "$AV/dd"; build nmsim1 cold
install_launch nmsim1 "$UA" "first install"
f="$SRC/IceCubesApp/App/Tabs/ToolbarTab.swift"; echo "// a $(date +%s)" >> "$f"; chown nmsim1 "$f"
build nmsim1 onefile-a
install_launch nmsim1 "$UA" "reinstall"
echo "// b $(date +%s)" >> "$f"; build nmsim1 onefile-a2
quick_install nmsim1 "$UA" "quick install"
finish nmsim1 a
sleep 3; echo "  3 s later: nmsim1 has $(pgrep -u nmsim1 | wc -l | tr -d ' ') processes ($(ps -o comm= -u nmsim1 | xargs -n1 basename 2>/dev/null | sort | tr '\n' ' '))"
echo "== session B: nmsim2, the same account"
start nmsim2 b; UB=$UDID; DEST=$UB
mount_account nmsim2
build nmsim2 nochange
echo "// c $(date +%s)" >> "$f"; chown nmsim2 "$f"; build nmsim2 onefile-b
install_launch nmsim2 "$UB" "install in a new session"
find "$SRC" -name '*.swift' -exec touch {} +; build nmsim2 touchall
echo "  relocation: the account volume renamed"; diskutil rename "$ACCT" "${ACCT}x" >/dev/null; AV=/Volumes/${ACCT}x; SRC=$AV/src/IceCubesApp; build nmsim2 moved
diskutil rename "${ACCT}x" "$ACCT" >/dev/null; AV=/Volumes/$ACCT; SRC=$AV/src/IceCubesApp
finish nmsim2 b
