# Do file-change events reach a pool user's Node on the session volume (mounted at ~/Library/Developer) and on /tmp?
as() { local u=$1; shift; launchctl asuser "$(id -u "$u")" sudo -u "$u" -H "$@"; }
container=$(diskutil info / | awk -F': *' '/APFS Container:/ {print $2}' | tr -d ' ')
H=/Users/nmsim1; NODE=/usr/local/nomac-test/node/bin/node
diskutil apfs addVolume "$container" APFS nms-fw -quota 1g -nomount >/dev/null; mkdir -p $H/Library/Developer; diskutil mount -mountPoint $H/Library/Developer nms-fw >/dev/null; mdutil -i off $H/Library/Developer >/dev/null 2>&1
chown nmsim1:staff $H/Library/Developer; mkdir -p $H/Library/Developer/w /tmp/fw-nmsim1; chown nmsim1:staff $H/Library/Developer/w /tmp/fw-nmsim1
echo a > $H/Library/Developer/w/App.js; echo a > /tmp/fw-nmsim1/App.js; chown nmsim1 $H/Library/Developer/w/App.js /tmp/fw-nmsim1/App.js
ls -la $H/Library/Developer/ | grep fseventsd
cat > /tmp/fw.js <<'JS'
const fs = require("fs"); const dirs = process.argv.slice(2); const t0 = Date.now();
for (const d of dirs) fs.watch(d, { recursive: true }, (ev, f) => console.log(`${((Date.now() - t0) / 1000).toFixed(2)} ${d} ${ev} ${f}`));
setTimeout(() => process.exit(0), 6000);
JS
as nmsim1 $NODE /tmp/fw.js $H/Library/Developer/w /tmp/fw-nmsim1 > /tmp/fw.out 2>&1 &
sleep 1.5
as nmsim1 sh -c "echo b >> $H/Library/Developer/w/App.js; echo b >> /tmp/fw-nmsim1/App.js"
sleep 1
python3 -c "open('$H/Library/Developer/w/App.js','a').write('c'); open('/tmp/fw-nmsim1/App.js','a').write('c')"
wait
echo "events seen by the pool user's Node (a write by the user at 1.5 s, by root at 2.5 s):"; cat /tmp/fw.out
diskutil unmount $H/Library/Developer >/dev/null; d=$(diskutil list | awk '/ nms-fw / {print $NF}'); diskutil apfs deleteVolume $d >/dev/null; rm -rf /tmp/fw-nmsim1 /tmp/fw.js
