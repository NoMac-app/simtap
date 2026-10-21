# E3d: warm xcodebuild and the phone's installer before handout; E3e: the account's cache archived, restored at the same path, rebuilt.
for u in 507 508; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim1 >/dev/null
P=/usr/local/nomac-test/prewarm
mkdir -p $P && cp -R /tmp/pw-upload/pkg /tmp/pw-upload/app $P/ && chmod -R a+rX $P
if [ ! -d $P/Prewarm.app ]; then
  xcrun -sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=17.0 -fobjc-arc $P/app/main.m -framework UIKit -o /tmp/Prewarm
  mkdir -p $P/Prewarm.app && cp /tmp/Prewarm $P/Prewarm.app/ && cp $P/app/Info.plist $P/Prewarm.app/ && codesign -s - $P/Prewarm.app 2>/dev/null; chmod -R a+rX $P
fi
start nmsim1 w; DEST=$UDID
echo "== warm-up as the pool user, before handout"
t=$(now); as nmsim1 xcodebuild -version >/dev/null 2>&1; echo "  xcodebuild -version: $(el $t) s"; t=$(now); as nmsim1 xcodebuild -version >/dev/null 2>&1; echo "  again: $(el $t) s"
t=$(now); as nmsim1 sh -c "cd /tmp && rm -rf pw-src && cp -R $P/pkg pw-src && cd pw-src && xcodebuild -scheme Prewarm -destination 'platform=iOS Simulator,id=$DEST' -derivedDataPath ~/Library/Developer/prewarm-dd build" > /tmp/e3d-prewarm.log 2>&1; echo "  a tiny package built: $(el $t) s ($(grep -E '^\*\* BUILD' /tmp/e3d-prewarm.log))"
t=$(now); as nmsim1 xcrun simctl install "$DEST" $P/Prewarm.app; echo "  a tiny app installed: $(el $t) s"
t=$(now); as nmsim1 xcrun simctl launch "$DEST" app.nomac.prewarm >/dev/null; as nmsim1 xcrun simctl terminate "$DEST" app.nomac.prewarm; as nmsim1 xcrun simctl uninstall "$DEST" app.nomac.prewarm; echo "  launched, ended, removed: $(el $t) s"
echo "== the customer's first build and install"
mount_account nmsim1
build nmsim1 warm-nochange
f="$SRC/IceCubesApp/App/Tabs/ToolbarTab.swift"; echo "// w $(date +%s)" >> "$f"; chown nmsim1 "$f"; build nmsim1 warm-onefile
install_launch nmsim1 "$DEST" "first install after the warm-up"
echo "== E3e: the cache moved to another host (archived, volume deleted, restored at the same path)"
as nmsim1 xcrun simctl shutdown all >/dev/null 2>&1; launchctl bootout user/507 2>/dev/null; pkill -9 -u 507; sleep 0.5
t=$(now); aa archive -d "$AV" -o /tmp/acct1.aar -a lzfse 2>/tmp/aa.err; echo "  archived (Apple Archive, lzfse): $(el $t) s, $(du -sh "$AV" | cut -f1) to $(du -h /tmp/acct1.aar | cut -f1)"
diskutil unmount "$AV" >/dev/null; dev=$(diskutil list | awk -v v="$ACCT" '$0 ~ " "v" " {print $NF}' | head -1); diskutil apfs deleteVolume "$dev" >/dev/null && echo "  account volume deleted"
diskutil apfs addVolume "$container" APFS "$ACCT" -quota 20g >/dev/null; mdutil -i off "$AV" >/dev/null 2>&1
t=$(now); aa extract -d "$AV" -i /tmp/acct1.aar 2>>/tmp/aa.err; echo "  restored into a new volume at the same path: $(el $t) s"
as nmsim1 xcrun simctl boot "$DEST" >/dev/null 2>&1; as nmsim1 perl -e 'alarm 90; exec @ARGV' xcrun simctl bootstatus "$DEST" -b >/dev/null
mount_account nmsim1
build nmsim1 restored-nochange
echo "// r $(date +%s)" >> "$f"; chown nmsim1 "$f"; build nmsim1 restored-onefile
finish nmsim1 w
