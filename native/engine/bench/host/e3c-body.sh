tbuild() { # user label: a no-change build with each line timestamped
  local u=$1 label=$2; local t=$(now)
  as "$u" xcodebuild -project "$SRC/IceCubesApp.xcodeproj" -scheme IceCubesApp -destination "platform=iOS Simulator,id=$DEST" \
    -derivedDataPath "$AV/dd" -clonedSourcePackagesDirPath "$AV/spm" -packageCachePath "$AV/spmcache" $FLAGS \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | python3 /tmp/ts.py > "/tmp/e3c-$label.log"
  echo "  $label: $(el $t) s, $(grep -c ' SwiftCompile ' /tmp/e3c-$label.log) compiles, description $(grep -o 'signature: [0-9a-f]*' /tmp/e3c-$label.log | cut -c12-19)"
  awk 'BEGIN{p=0} {d=$1-p; if (d > 0.8) printf "      +%.1f s before: %s %s %s\n", d, $2, $3, $4; p=$1}' "/tmp/e3c-$label.log" | head -8
}
for u in 507 508; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
for v in nms-c nms-d; do d=$(diskutil list | awk -v v="$v" '$0 ~ " "v" " {print $NF}' | head -1); [ -n "$d" ] && diskutil apfs deleteVolume "$d" >/dev/null; done
wipe_home nmsim1 >/dev/null; wipe_home nmsim2 >/dev/null
echo "== session C: nmsim1"
start nmsim1 c; UC=$UDID; DEST=$UC
mount_account nmsim1
tbuild nmsim1 c1; tbuild nmsim1 c2
D=/Users/nmsim1/Library/Developer/CoreSimulator/Devices; U2=$(uuidgen); cp -R "$GOLDEN" "$D/$U2"; /usr/libexec/PlistBuddy -c "Set :UDID $U2" "$D/$U2/device.plist"; chown -R nmsim1:staff "$D/$U2"
as nmsim1 xcrun simctl boot "$U2"; as nmsim1 xcrun simctl bootstatus "$U2" -b >/dev/null
DEST=$U2; tbuild nmsim1 c3-other-phone
DEST=$UC
finish nmsim1 c
echo "== session D: nmsim2, a phone with the same UDID as session C's"
start nmsim2 d
D=/Users/nmsim2/Library/Developer/CoreSimulator/Devices; as nmsim2 xcrun simctl shutdown "$UDID"
launchctl bootout user/508 2>/dev/null; pkill -9 -u 508; sleep 0.5
mv "$D/$UDID" "$D/$UC"; /usr/libexec/PlistBuddy -c "Set :UDID $UC" "$D/$UC/device.plist"
as nmsim2 xcrun simctl boot "$UC"; as nmsim2 xcrun simctl bootstatus "$UC" -b >/dev/null; DEST=$UC
mount_account nmsim2
tbuild nmsim2 d1; tbuild nmsim2 d2
finish nmsim2 d
