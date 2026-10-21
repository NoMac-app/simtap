# Real MCP tool calls through `simulator-use mcp` (stdio), timed, with the engine on or off.
import json, subprocess, sys, time, os, statistics
UDID, MODE, ROUNDS = sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 3
BIN = "/usr/local/nomac-test/su-next/bin/simulator-use"
env = dict(os.environ, PATH="/usr/local/nomac-test/node/bin:" + os.environ["PATH"], SIMULATOR_USE_NO_UPDATE="1")
if MODE == "off": env["SIMULATOR_USE_ENGINE"] = "off"
p = subprocess.Popen([BIN, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1, env=env)
n = 0
def rpc(method, params=None, notify=False):
    global n
    msg = {"jsonrpc": "2.0", "method": method, **({"params": params} if params is not None else {})}
    if not notify: n += 1; msg["id"] = n
    p.stdin.write(json.dumps(msg) + "\n"); p.stdin.flush()
    if notify: return None
    while True:
        a = json.loads(p.stdout.readline())
        if a.get("id") == n: return a
def tool(name, args):
    t = time.time(); a = rpc("tools/call", {"name": name, "arguments": args}); ms = (time.time() - t) * 1000
    res = a.get("result", {}); text = " ".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
    return ms, res.get("isError", False), text
rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "bench", "version": "1"}}); rpc("notifications/initialized", notify=True)
print("device_use", tool("device_use", {"device": UDID})[:2], flush=True)
plan = [("look", "ui_look", {}), ("act: home", "ui_act", {"steps": ["home"]}), ("act: tap Settings", "ui_act", {"steps": ['tap "Settings"']}),
        ("act: tap General", "ui_act", {"steps": ['tap "General"']}), ("act: back", "ui_act", {"steps": ["back"]}), ("look + screenshot", "ui_look", {"screenshot": True})]
times = {name: [] for name, _, _ in plan}; errors = []
for r in range(ROUNDS):
    for name, t, args in plan:
        ms, err, text = tool(t, args); times[name].append(ms)
        if err: errors.append(f"{name}: {text[:120]}")
        if r == 0 and name in ("act: tap Settings", "act: tap General"): print(f"  {name} said: {text[:160]!r}", flush=True)
print(f"engine {MODE}:", flush=True)
for name, v in times.items(): print(f"  {name:20} p50 {statistics.median(v):6.0f} ms  max {max(v):6.0f} ms  {[round(x) for x in v]}", flush=True)
if errors: print("  errors:", errors[:6], flush=True)
p.stdin.close(); p.wait()
