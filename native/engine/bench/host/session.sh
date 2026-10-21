#!/bin/bash
# A NoMac Simulator session's life on a host, as hostd would run it (prototype; run as root).
#   session.sh users                      make the pool users nmsim1..nmsimN (once; macOS 27 cannot delete them over SSH)
#   session.sh golden <source-udid> <owner>  copy a golden phone into /Library/NoMacSim/golden (root-owned, read-only)
#   session.sh start <user> <session>     volume, phone copied from the golden, booted as the user; prints timings and the UDID
#   session.sh end <user> <session>       the user's processes ended, the volume deleted
set -u
now() { python3 -c 'import time;print(time.time())'; }
el() { python3 -c "print(round($(now) - $1, 2))"; }
GOLDEN_ROOT=/Library/NoMacSim/golden
container=$(diskutil info / | awk -F': *' '/APFS Container:/ {print $2}' | tr -d ' ')
as() { local u=$1; shift; launchctl asuser "$(id -u "$u")" sudo -u "$u" -H "$@"; }
case "$1" in
users)
  for i in $(seq 1 "${2:-2}"); do u=nmsim$i
    id "$u" >/dev/null 2>&1 || { sysadminctl -addUser "$u" -fullName "NoMac Simulator $i" -password "$(openssl rand -hex 24)" -home "/Users/$u" >/dev/null 2>&1; createhomedir -c -u "$u" >/dev/null 2>&1; }
    dscl . -create "/Users/$u" IsHidden 1; chmod 700 "/Users/$u"; echo "$u uid $(id -u "$u")"
  done ;;
golden)
  src=$(eval echo "~$3")/Library/Developer/CoreSimulator/Devices/$2
  t=$(now); mkdir -p "$GOLDEN_ROOT"; rm -rf "$GOLDEN_ROOT/current"; cp -c -R "$src" "$GOLDEN_ROOT/current"
  chown -R root:wheel "$GOLDEN_ROOT"; chmod -R go-w "$GOLDEN_ROOT"; chmod 755 "$GOLDEN_ROOT" "$GOLDEN_ROOT/current"
  echo "golden copied in $(el $t) s ($(du -sh "$GOLDEN_ROOT/current" | cut -f1))" ;;
start)
  u=$2; s=$3; vol=nms-$s; t0=$(now)
  diskutil apfs addVolume "$container" APFS "$vol" -quota 20g >/dev/null || { echo "volume failed"; exit 1; }
  chown "$u":staff "/Volumes/$vol"; chmod 700 "/Volumes/$vol"; t1=$(now)
  set_dir=/Volumes/$vol/devices; mkdir -p "$set_dir"; udid=$(uuidgen)
  cp -R "$GOLDEN_ROOT/current" "$set_dir/$udid"
  /usr/libexec/PlistBuddy -c "Set :UDID $udid" -c "Set :name phone" "$set_dir/$udid/device.plist"
  chown -R "$u":staff "$set_dir"; t2=$(now)
  as "$u" xcrun simctl --set "$set_dir" boot "$udid" && as "$u" xcrun simctl --set "$set_dir" bootstatus "$udid" -b >/dev/null; t3=$(now)
  echo "session $s for $u: volume $(python3 -c "print(round($t1-$t0,2))") s, phone copied $(python3 -c "print(round($t2-$t1,2))") s, booted $(python3 -c "print(round($t3-$t2,2))") s"
  echo "UDID=$udid SET=$set_dir" ;;
end)
  u=$2; s=$3; vol=nms-$s; t0=$(now)
  as "$u" xcrun simctl --set "/Volumes/$vol/devices" shutdown all >/dev/null 2>&1
  pkill -u "$u" -f simulator-use-engine; sleep 1
  dev=$(diskutil list | awk -v v="$vol" '$0 ~ " "v" " {print $NF}' | head -1)
  [ -n "$dev" ] && diskutil apfs deleteVolume "$dev" >/dev/null && echo "session $s ended in $(el $t0) s (volume deleted)" || echo "volume not found or not deleted" ;;
esac
