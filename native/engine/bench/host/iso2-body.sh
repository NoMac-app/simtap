# T10 (one tenant against another) and T15 (pf per pool user), two live sessions: A = nmsim1, B = nmsim2.
ok() { if [ "$1" = 0 ]; then echo "REACHED"; else echo "blocked"; fi; }
# Every probe ends within 20 s (macOS has no timeout command).
tryB() { as nmsim2 perl -e 'alarm shift; exec @ARGV' 20 sh -c "$1" >/dev/null 2>&1; ok $?; }
tryA() { as nmsim1 perl -e 'alarm shift; exec @ARGV' 20 sh -c "$1" >/dev/null 2>&1; ok $?; }
for u in 507 508; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
for v in nms-ia nms-ib nms-ja nms-jb; do d=$(diskutil list | awk -v v="$v" '$0 ~ " "v" " {print $NF}' | head -1); [ -n "$d" ] && diskutil apfs deleteVolume "$d" >/dev/null; done
wipe_home nmsim1 >/dev/null; wipe_home nmsim2 >/dev/null
start nmsim1 ja; UA=$UDID
start nmsim2 jb; UB=$UDID
mount_account nmsim1
echo "== A does ordinary work"
as nmsim1 sh -c 'echo "token=SECRET-A" > /tmp/a-build-output.txt; echo SECRET-A-CLIP | pbcopy; mkdir -p ~/Library/Developer/srv && echo SECRET-A-SRV > ~/Library/Developer/srv/index.html'
as nmsim1 sh -c 'cd ~/Library/Developer/srv && exec python3 -m http.server 8765 --bind 127.0.0.1' >/dev/null 2>&1 &
as nmsim1 sh -c 'cd ~/Library/Developer/srv && exec python3 -m http.server 20150 --bind 127.0.0.1' >/dev/null 2>&1 &
as nmsim1 sh -c "exec sleep 600 /Volumes/nma-acct1/src/IceCubesApp/secret-arg API_KEY=abc123" >/dev/null 2>&1 &
sleep 2; APID=$(pgrep -u nmsim1 -f "sleep 600" | head -1)
echo "== T15: pf rules per pool user"
cp /etc/pf.anchors/app.nomac.vm-display /tmp/vm-display.orig
{ cat /etc/pf.anchors/app.nomac.vm-display; echo 'anchor "sim"'; } > /tmp/vm-display.with-sim
cat > /tmp/sim.rules <<'RULES'
# NoMac Simulator pool users: loopback only inside their own port range (and only they may serve it), no private networks, no SMTP.
block drop out quick on lo0 proto tcp from any to any port 20100 <> 20199 user nmsim1 flags S/SA
block drop out quick on lo0 proto tcp from any to any port 20200 <> 20299 user nmsim2 flags S/SA
block drop in quick on lo0 proto tcp from any to any port 20100:20199 user != nmsim1 flags S/SA
block drop in quick on lo0 proto tcp from any to any port 20200:20299 user != nmsim2 flags S/SA
block drop out quick proto tcp from any to { 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10 fc00::/7 fe80::/10 } user { nmsim1 nmsim2 } flags S/SA
block drop out quick proto udp from any to { 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10 fc00::/7 fe80::/10 } user { nmsim1 nmsim2 }
block drop out quick proto tcp from any to any port { 25 465 587 } user { nmsim1 nmsim2 } flags S/SA
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

echo "== T9: B's phone while A burns CPU (12 threads)"
reads() { # n: B's whole-screen read times, p50 and p90
  printf '{"op":"describe"}\n%.0s' $(seq 1 $1) | as nmsim2 /usr/local/nomac-test/engine/simulator-use-engine --udid $UB | python3 -c '
import sys, json
ms = sorted(json.loads(l).get("ms", 0) for l in sys.stdin if "tree" in l)
print("p50 %d ms, p90 %d ms (%d reads)" % (ms[len(ms)//2], ms[int(len(ms)*0.9)], len(ms)) if ms else "no reads")'
}
burn() { for i in $(seq 1 12); do as nmsim1 $1 sh -c 'exec yes' >/dev/null 2>&1 & done; sleep 2; }
echo "  quiet: $(reads 15), load $(sysctl -n vm.loadavg | cut -d' ' -f2)"
burn ""; echo "  A burning at normal priority: $(reads 15), load $(sysctl -n vm.loadavg | cut -d' ' -f2)"
for p in $(pgrep -u nmsim1 -x yes); do taskpolicy -b -p $p; done
echo "  A's burners set to background by root: $(reads 15)"
for p in $(pgrep -u nmsim1 -x yes); do as nmsim1 taskpolicy -B -p $p 2>/dev/null; done
echo "  A tried to undo it (taskpolicy -B as A): $(reads 15)"
pkill -9 -u nmsim1 -x yes; sleep 1
burn "taskpolicy -c background"; echo "  A's burners started clamped (taskpolicy -c background): $(reads 15)"
for p in $(pgrep -u nmsim1 -x yes); do as nmsim1 taskpolicy -B -p $p 2>/dev/null; as nmsim1 renice -n 0 -p $p >/dev/null 2>&1; done
echo "  A tried to undo the clamp: $(reads 15)"
pkill -9 -u nmsim1 -x yes; sleep 1
echo "  quiet again: $(reads 15)"
pkill -u 507 -f http.server; pkill -u 508 -f http.server; rm -f /tmp/a-build-output.txt
finish nmsim1 ja; finish nmsim2 jb
