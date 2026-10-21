for u in 507 508; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim1 >/dev/null; wipe_home nmsim2 >/dev/null
start nmsim1 ta; UA=$UDID
start nmsim2 tb; UB=$UDID
echo "  phones settling 40 s"; sleep 40
python3 /tmp/t9.py "$UB"
finish nmsim1 ta; finish nmsim2 tb
