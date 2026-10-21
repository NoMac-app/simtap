# E3e: an account's cache moved to another host: cold build, archive (checked before anything is deleted), upload to
# R2, download, restore into a new volume at the same path, rebuild. As the pool user nmsim1. Needs /tmp/presigned.env.
. /tmp/presigned.env
for u in 507; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim1 >/dev/null
start nmsim1 mv2; DEST=$UDID
diskutil info "$ACCT" >/dev/null 2>&1 || { diskutil apfs addVolume "$container" APFS "$ACCT" -quota 20g >/dev/null; echo "  account volume made"; }
mount_account nmsim1
mkdir -p "$AV/src"; rsync -a --delete --exclude .git ~rentamac/IceCubesApp/ "$SRC/"; chown -R nmsim1:staff "$AV/src"
build nmsim1 mv-cold
X="-exclude-name .Spotlight-V100 -exclude-name .Trashes -exclude-name .fseventsd"
t=$(now); aa archive -d "$AV" -o /tmp/acct1.aar $X -a lzfse 2>/tmp/aa.err; rc=$?
n_arch=$(aa list -i /tmp/acct1.aar 2>/dev/null | wc -l | tr -d ' '); n_vol=$(find "$AV/src" "$AV/dd" "$AV/spm" "$AV/spmcache" 2>/dev/null | wc -l | tr -d ' ')
echo "  archived (lzfse): exit $rc in $(el $t) s, $(du -sh "$AV" 2>/dev/null | cut -f1) to $(du -h /tmp/acct1.aar | cut -f1), $n_arch entries for $n_vol on the volume"
if [ $rc != 0 ] || [ $n_arch -lt $((n_vol - 10)) ]; then echo "  ARCHIVE INCOMPLETE: stopping before anything is deleted"; cat /tmp/aa.err | head -3; finish nmsim1 mv2; exit 1; fi
t=$(now); curl -fsS -T /tmp/acct1.aar "$PUT" -o /dev/null -w "%{speed_upload}" > /tmp/up.speed; echo "  uploaded to R2: $(el $t) s ($(python3 -c "print(round($(cat /tmp/up.speed)/1e6,1))") MB/s)"
t=$(now); curl -fsS "$GET" -o /tmp/acct1-down.aar -w "%{speed_download}" > /tmp/down.speed; echo "  downloaded from R2: $(el $t) s ($(python3 -c "print(round($(cat /tmp/down.speed)/1e6,1))") MB/s), same bytes: $(cmp -s /tmp/acct1.aar /tmp/acct1-down.aar && echo yes || echo NO)"
as nmsim1 xcrun simctl shutdown all >/dev/null 2>&1; launchctl bootout user/507 2>/dev/null; pkill -9 -u 507; sleep 0.5
diskutil unmount "$AV" >/dev/null; dev=$(diskutil list | awk -v v="$ACCT" '$0 ~ " "v" " {print $NF}' | head -1); diskutil apfs deleteVolume "$dev" >/dev/null && echo "  account volume deleted"
diskutil apfs addVolume "$container" APFS "$ACCT" -quota 20g >/dev/null; mdutil -i off "$AV" >/dev/null 2>&1
t=$(now); aa extract -d "$AV" -i /tmp/acct1-down.aar 2>>/tmp/aa.err; echo "  restored into a new volume at the same path: exit $? in $(el $t) s ($(du -sh "$AV" 2>/dev/null | cut -f1))"
as nmsim1 xcrun simctl boot "$DEST" >/dev/null 2>&1; as nmsim1 perl -e 'alarm 90; exec @ARGV' xcrun simctl bootstatus "$DEST" -b >/dev/null
mount_account nmsim1
build nmsim1 mv-restored-nochange
f="$SRC/IceCubesApp/App/Tabs/ToolbarTab.swift"; echo "// r $(date +%s)" >> "$f"; chown nmsim1 "$f"; build nmsim1 mv-restored-onefile
curl -fsS -X DELETE "$DELETE" -o /dev/null && echo "  R2 object deleted"; rm -f /tmp/acct1.aar /tmp/acct1-down.aar /tmp/presigned.env
finish nmsim1 mv2
