# simulator-use itself, as the pool user, typing text the keyboard cannot type: its paste falls back to the helper.
L=/usr/local/nomac-test/su-next/lib/node_modules/simulator-use
tar -xzf /tmp/su-dist.tgz -C $L && chmod -R a+rX $L && echo "  simulator-use updated (dist and the helper)"
for u in 507; do launchctl bootout user/$u 2>/dev/null; pkill -9 -u $u; done; sleep 0.5
wipe_home nmsim1 >/dev/null
start nmsim1 sp2; U=$UDID; sleep 30
t=$(now); out=$(as nmsim1 env PATH=/usr/local/nomac-test/node/bin:/usr/bin:/bin SIMULATOR_USE_ENGINE=/usr/local/nomac-test/engine/simulator-use-engine perl -e 'alarm 90; exec @ARGV' /usr/local/nomac-test/su-next/bin/simulator-use act 'swipe down' 'type "Héllo 日本 🙂"' 2>&1)
echo "  act 'swipe down' 'type \"Héllo 日本 🙂\"': exit $? in $(el $t) s"; echo "    lines with the typed text: $(echo "$out" | grep -c 'Héllo 日本 🙂')"; echo "$out" | grep 'Héllo\|field\|search' | head -4 | sed 's/^/    /'
finish nmsim1 sp2
