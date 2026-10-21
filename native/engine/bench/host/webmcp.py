# simulator-use's own MCP tools on a web page, as the pool user nmsim2, with the engine that scans web content:
# ui_look on WebTest (twice), ui_act filling the form and tapping Continue, ui_look for the page's answer; Settings
# for a native screen. Usage (as root): webmcp.py <udid>
import json, os, subprocess, sys, time
udid = sys.argv[1]
AS = ["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H", "env",
      "PATH=/usr/local/nomac-test/node/bin:/usr/bin:/bin", "SIMULATOR_USE_NO_UPDATE=1",
      "SIMULATOR_USE_ENGINE=/usr/local/nomac-test/engine/simulator-use-engine.web"]
p = subprocess.Popen(AS + ["/usr/local/nomac-test/su-next/bin/simulator-use", "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
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
def tool(label, name, args, show=True):
    t = time.time(); a = rpc("tools/call", {"name": name, "arguments": args}); ms = int((time.time() - t) * 1000)
    res = a.get("result", {}); text = "\n".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
    print(f"== {label}: {ms} ms{' (error)' if res.get('isError') else ''}", flush=True)
    if show: print("\n".join("   " + l for l in text.splitlines()[:30]), flush=True)
    return text
rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "webmcp", "version": "1"}}); rpc("notifications/initialized", notify=True)
tool("device_use", "device_use", {"device": udid}, show=False)
subprocess.run(["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H", "xcrun", "simctl", "launch", udid, "app.nomac.webtest"], capture_output=True); time.sleep(5)
tool("ui_look on WebTest", "ui_look", {})
tool("ui_look again (unchanged screen)", "ui_look", {}, show=False)
tool('ui_act: fill "Email", tap "Continue"', "ui_act", {"steps": ['fill "Email" agent@nomac.app', 'tap "Continue"']})
out = tool("ui_look after", "ui_look", {}, show=False)
print(f"   the page's answer listed: {'Signed in as agent@nomac.app' in out}", flush=True)
subprocess.run(["launchctl", "asuser", "508", "sudo", "-u", "nmsim2", "-H", "xcrun", "simctl", "launch", udid, "com.apple.Preferences"], capture_output=True); time.sleep(3)
tool("ui_look on Settings (native)", "ui_look", {}, show=False)
tool("ui_look on Settings again", "ui_look", {}, show=False)
p.stdin.close(); p.wait(timeout=20)
