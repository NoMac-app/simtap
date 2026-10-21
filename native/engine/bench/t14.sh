#!/bin/bash
# T14 (as root): a per-session APFS volume with a quota holding that session's device set; a phone copied
# in from a root-owned golden by APFS clone (cp -c) and given a new UDID; booted from that set; wiped by
# deleting and recreating the volume. Uses the logged-in user so CoreSimulator runs in a session.
set -u
USER_NAME=${1:-rentamac}; GOLD_UDID=${2:?golden UDID}; VOL=nomac-t14
uid=$(id -u "$USER_NAME"); as() { launchctl asuser "$uid" sudo -u "$USER_NAME" -H "$@"; }
now() { python3 -c 'import time;print(time.time())'; }
container=$(diskutil info / | awk -F': *' '/APFS Container:/ {print $2}' | tr -d ' ')
SRC=/Users/$USER_NAME/Library/Developer/CoreSimulator/Devices/$GOLD_UDID
GOLDEN=/Library/NoMacSim/golden/$GOLD_UDID
as xcrun simctl shutdown "$GOLD_UDID" >/dev/null 2>&1
t0=$(now); mkdir -p /Library/NoMacSim/golden; rm -rf "$GOLDEN"; cp -c -R "$SRC" "$GOLDEN"; chown -R root:wheel "$GOLDEN"; chmod -R go-w "$GOLDEN"; t1=$(now)
echo "golden copied to a root-owned folder by APFS clone in $(echo "$t1-$t0" | bc) s ($(du -sh "$GOLDEN" | cut -f1) logical)"
for round in 1 2; do
  t0=$(now)
  diskutil apfs addVolume "$container" APFS "$VOL" -quota 20g >/dev/null || { echo "addVolume failed"; exit 1; }
  chown "$USER_NAME" "/Volumes/$VOL"; t1=$(now)
  SET=/Volumes/$VOL/devices; as mkdir -p "$SET"
  NEW=$(uuidgen); cp -c -R "$GOLDEN" "$SET/$NEW"; chown -R "$USER_NAME" "$SET/$NEW"
  /usr/libexec/PlistBuddy -c "Set :UDID $NEW" -c "Set :name t14-$round" "$SET/$NEW/device.plist"; t2=$(now)
  as xcrun simctl --set "$SET" list devices | grep -q "$NEW" && listed=yes || listed=no
  as xcrun simctl --set "$SET" boot "$NEW"; as xcrun simctl --set "$SET" bootstatus "$NEW" -b >/dev/null; t3=$(now)
  shot=$(as xcrun simctl --set "$SET" io "$NEW" screenshot /tmp/t14-$round.png >/dev/null 2>&1 && echo ok || echo failed)
  echo "round $round: volume $(echo "$t1-$t0"|bc) s, phone cloned in $(echo "$t2-$t1"|bc) s (listed: $listed), booted $(echo "$t3-$t2"|bc) s, screenshot $shot; quota: $(diskutil apfs list | grep -A8 "$VOL" | grep -i quota | head -1 | sed 's/^ *//')"
  # the user cannot write into the golden
  as touch "$GOLDEN/x" 2>/dev/null && echo "  WARNING: the user can write into the golden" || echo "  the user cannot change the golden"
  t4=$(now); as xcrun simctl --set "$SET" shutdown "$NEW" >/dev/null 2>&1
  vol=$(diskutil list | awk -v v="$VOL" '$0 ~ v {print $NF}' | head -1)
  diskutil apfs deleteVolume "$vol" >/dev/null && t5=$(now) && echo "  wiped (volume deleted) in $(echo "$t5-$t4"|bc) s, including the phone's shutdown"
done
