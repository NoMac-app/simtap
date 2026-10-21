# Pool refill soak: sessions started and ended back to back, users alternating; every phone checked with a real read.
N=${N:-12}; hung=0; unread=0
for u in 507 508; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
for v in nms-d nms-ia nms-ib nms-ja nms-jb; do d=$(diskutil list | awk -v v="$v" '$0 ~ " "v" " {print $NF}' | head -1); [ -n "$d" ] && diskutil apfs deleteVolume "$d" >/dev/null; done
wipe_home nmsim1 >/dev/null; wipe_home nmsim2 >/dev/null
before=$(ls /Library/Logs/DiagnosticReports | grep -c notifyd)
for i in $(seq 1 $N); do
  u=nmsim$(( (i % 2) + 1 )); t0=$(now)
  start "$u" "k$i"
  if [ $BOOT_OK = 0 ]; then
    if [ $((i % 2)) = 0 ]; then wait_s=30; else wait_s=0; fi; sleep $wait_s
    t=$(now); r=$(printf '%s\n' '{"op":"describe"}' '{"op":"describe"}' | as "$u" perl -e 'alarm shift; exec @ARGV' 60 /usr/local/nomac-test/engine/simulator-use-engine --udid "$UDID" | python3 /tmp/read.py | tr '\n' ' ')
    sleep 1; r2=$(printf '%s\n' '{"op":"describe"}' | as "$u" perl -e 'alarm shift; exec @ARGV' 60 /usr/local/nomac-test/engine/simulator-use-engine --udid "$UDID" | python3 /tmp/read.py | tail -1)
    echo "  $i: first engine after a ${wait_s} s wait: $(echo "$r" | cut -c1-24) / $(echo "$r" | awk -F'read ' '{print $3}' | cut -c1-10) [$(el $t) s]; a second engine: $(echo "$r2" | cut -c1-24)"
    echo "$r$r2" | grep -q "error" && unread=$((unread + 1))
  else hung=$((hung + 1)); fi
  finish "$u" "k$i"; echo "  $i: whole cycle $(el $t0) s"
done
echo "== $N boots: $hung hung, $unread booted but unreadable, $(( $(ls /Library/Logs/DiagnosticReports | grep -c notifyd) - before )) new notifyd crash reports"
