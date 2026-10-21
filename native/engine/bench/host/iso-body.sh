# T10 (one tenant against another) and T15 (pf per pool user), two live sessions: A = nmsim1, B = nmsim2.
ok() { if [ "$1" = 0 ]; then echo "REACHED"; else echo "blocked"; fi; }
# Every probe ends within 20 s (macOS has no timeout command).
tryB() { as nmsim2 perl -e 'alarm shift; exec @ARGV' 20 sh -c "$1" >/dev/null 2>&1; ok $?; }
tryA() { as nmsim1 perl -e 'alarm shift; exec @ARGV' 20 sh -c "$1" >/dev/null 2>&1; ok $?; }
for u in 507 508; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
for v in nms-ia nms-ib; do d=$(diskutil list | awk -v v="$v" '$0 ~ " "v" " {print $NF}' | head -1); [ -n "$d" ] && diskutil apfs deleteVolume "$d" >/dev/null; done
wipe_home nmsim1 >/dev/null; wipe_home nmsim2 >/dev/null
start nmsim1 ia; UA=$UDID
start nmsim2 ib; UB=$UDID
mount_account nmsim1
echo "== A does ordinary work"
as nmsim1 sh -c 'echo "token=SECRET-A" > /tmp/a-build-output.txt; echo SECRET-A-CLIP | pbcopy; mkdir -p ~/Library/Developer/srv && echo SECRET-A-SRV > ~/Library/Developer/srv/index.html'
as nmsim1 sh -c 'cd ~/Library/Developer/srv && exec python3 -m http.server 8765 --bind 127.0.0.1' >/dev/null 2>&1 &
as nmsim1 sh -c 'cd ~/Library/Developer/srv && exec python3 -m http.server 20150 --bind 127.0.0.1' >/dev/null 2>&1 &
as nmsim1 sh -c "exec sleep 600 /Volumes/nma-acct1/src/IceCubesApp/secret-arg API_KEY=abc123" >/dev/null 2>&1 &
sleep 2; APID=$(pgrep -u nmsim1 -f "sleep 600" | head -1)
echo "== T10: what B can reach of A"
echo "  A's home: $(tryB 'ls /Users/nmsim1')"
echo "  A's session volume (phone, DerivedData): $(tryB 'ls /Users/nmsim1/Library/Developer')"
echo "  A's account volume: $(tryB 'ls /Volumes/nma-acct1')"
echo "  A's phone through B's simctl: $(tryB "xcrun simctl list devices | grep -q $UA")"
echo "  A's phone through the engine: $(tryB "printf '{\"op\":\"describe\"}\n' | /usr/local/nomac-test/engine/simulator-use-engine --udid $UA | grep -q tree")"
echo "  A's file in /tmp (A's umask 022): $(tryB 'cat /tmp/a-build-output.txt | grep -q SECRET-A')"
echo "  A's clipboard: $(tryB 'pbpaste | grep -q SECRET-A')"
echo "  A's local server on 8765: $(tryB 'curl -s -m 3 http://127.0.0.1:8765/ | grep -q SECRET-A')"
echo "  A's process list with arguments: $(tryB "ps -axww -o user,command | grep -q 'API_KEY=abc123'")"
echo "  A's process environment (ps -E): $(tryB "ps -E -p $APID -o command | grep -q HOME=/Users/nmsim1")"
echo "  signal A's process: $(tryB "kill -0 $APID")"
echo "  A's open files (lsof): $(tryB "lsof -p $APID | grep -q cwd")"
echo "  host logs naming A: $(tryB "log show --last 2m --style compact 2>/dev/null | grep -q nmsim1")"
echo "  mounted volume names: $(as nmsim2 sh -c 'mount | grep -o "/Volumes/nm[a-z]*-[a-z0-9]*\|/Users/nmsim[0-9]*/Library/Developer" | sort -u | tr "\n" " "')"
echo "  host SSH on 127.0.0.1:22: $(tryB 'nc -z -G 2 127.0.0.1 22')"
echo "  remote desktop agent on 127.0.0.1:45600: $(tryB 'nc -z -G 2 127.0.0.1 45600')"
echo "  the provider's LAN gateway (10.21.106.1:53/80/443): $(tryB 'nc -z -G 2 10.21.106.1 53 || nc -z -G 2 10.21.106.1 80 || nc -z -G 2 10.21.106.1 443')"
echo "  the internet (swift.org:443): $(tryB 'nc -z -G 3 swift.org 443')"
echo "  SMTP out (gmail-smtp-in.l.google.com:25): $(tryB 'nc -z -G 3 gmail-smtp-in.l.google.com 25')"
echo "  world-writable folders on the data volume: $(find /System/Volumes/Data -xdev -type d -perm -0002 -maxdepth 4 2>/dev/null | grep -v '/Volumes/Data/private/var/folders' | head -12 | tr '\n' ' ')"
echo "== T15: pf rules per pool user"
cp /etc/pf.anchors/app.nomac.vm-display /tmp/vm-display.orig
{ cat /etc/pf.anchors/app.nomac.vm-display; echo 'anchor "sim"'; } > /tmp/vm-display.with-sim
cat > /tmp/sim.rules <<'RULES'
# NoMac Simulator pool users: loopback only inside their own port range (and only they may serve it), no private networks, no SMTP.
block drop out quick on lo0 proto tcp user nmsim1 to any port 20100 <> 20199 flags S/SA
block drop out quick on lo0 proto tcp user nmsim2 to any port 20200 <> 20299 flags S/SA
block drop in quick on lo0 proto tcp to any port 20100:20199 user != nmsim1 flags S/SA
block drop in quick on lo0 proto tcp to any port 20200:20299 user != nmsim2 flags S/SA
block drop out quick proto tcp user { nmsim1 nmsim2 } to { 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10 fc00::/7 fe80::/10 } flags S/SA
block drop out quick proto udp user { nmsim1 nmsim2 } to { 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10 fc00::/7 fe80::/10 }
block drop out quick proto tcp user { nmsim1 nmsim2 } to any port { 25 465 587 } flags S/SA
RULES
pfctl -a app.nomac.vm-display -f /tmp/vm-display.with-sim 2>&1 | grep -v "ALTQ\|^$" ; pfctl -a app.nomac.vm-display/sim -f /tmp/sim.rules 2>&1 | grep -v "ALTQ\|^$"
echo "  rules: $(pfctl -a app.nomac.vm-display/sim -sr 2>/dev/null | wc -l | tr -d ' ') loaded; parent: $(pfctl -a app.nomac.vm-display -sr 2>/dev/null | tr '\n' ' ')"
echo "  A to its own server in its range (20150): $(tryA 'curl -s -m 3 http://127.0.0.1:20150/ | grep -q SECRET-A')"
echo "  A to its own server outside its range (8765): $(tryA 'curl -s -m 3 http://127.0.0.1:8765/ | grep -q SECRET-A')"
echo "  B to A's server (20150): $(tryB 'curl -s -m 3 http://127.0.0.1:20150/ | grep -q SECRET-A')"
echo "  B to A's server (8765): $(tryB 'curl -s -m 3 http://127.0.0.1:8765/ | grep -q SECRET-A')"
as nmsim2 sh -c 'cd /tmp && exec python3 -m http.server 20160 --bind 127.0.0.1' >/dev/null 2>&1 & sleep 1.5
echo "  A to B's squatter inside A's range (20160): $(tryA 'curl -s -m 3 http://127.0.0.1:20160/ >/dev/null')"
echo "  B to host SSH: $(tryB 'nc -z -G 2 127.0.0.1 22'); B to the remote desktop agent: $(tryB 'nc -z -G 2 127.0.0.1 45600'); B to the host's own address: $(tryB 'nc -z -G 2 10.21.106.113 22')"
echo "  B to the LAN gateway: $(tryB 'nc -z -G 2 10.21.106.1 53 || nc -z -G 2 10.21.106.1 80 || nc -z -G 2 10.21.106.1 443')"
echo "  B to the internet: $(tryB 'nc -z -G 3 swift.org 443'); B to SMTP: $(tryB 'nc -z -G 3 gmail-smtp-in.l.google.com 25'); B resolves names: $(tryB 'host -W 3 swift.org')"
echo "  B to IPv6 loopback ([::1]:22): $(tryB 'nc -6 -z -G 2 ::1 22')"
echo "  admin (rentamac) to host SSH, unaffected: $(sudo -u rentamac nc -z -G 2 127.0.0.1 22 >/dev/null 2>&1; ok $?)"
echo "  B's phone still reads: $(printf '{"op":"describe"}\n' | as nmsim2 /usr/local/nomac-test/engine/simulator-use-engine --udid $UB | python3 /tmp/read.py | tail -1 | cut -c1-60)"
pfctl -a app.nomac.vm-display/sim -F rules 2>/dev/null; pfctl -a app.nomac.vm-display -f /tmp/vm-display.orig 2>&1 | grep -v "ALTQ\|^$"
echo "  firewall restored: $(pfctl -a app.nomac.vm-display -sr 2>/dev/null | tr '\n' ' ')"
pkill -u 507 -f http.server; pkill -u 508 -f http.server; rm -f /tmp/a-build-output.txt
finish nmsim1 ia; finish nmsim2 ib
