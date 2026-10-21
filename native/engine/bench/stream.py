# 10 s of hardware video from one phone while a second engine swipes the home screen (motion).
import json, subprocess, sys, time, os, threading
E = os.path.expanduser("~/sue/sue-engine"); U = sys.argv[1]
def engine():
    p = subprocess.Popen([E, "--udid", U], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1); json.loads(p.stdout.readline()); return p
def call(p, req): p.stdin.write(json.dumps(req) + "\n"); p.stdin.flush(); return json.loads(p.stdout.readline())
mover = engine(); streamer = engine(); stop = False
def move():
    while not stop:
        call(mover, {"op": "swipe", "x1": 350, "y1": 500, "x2": 50, "y2": 500, "duration": 0.25}); time.sleep(0.7)
        call(mover, {"op": "swipe", "x1": 50, "y1": 500, "x2": 350, "y2": 500, "duration": 0.25}); time.sleep(0.7)
for transport, codec in [("fmp4", "h264"), ("annexb", "h264"), ("fmp4", "hevc")]:
    stop = False; th = threading.Thread(target=move); th.start()
    path = f"/tmp/sue-stream.{codec}.{transport}"
    a = call(streamer, {"op": "stream", "seconds": 10, "fps": 30, "codec": codec, "transport": transport, "scale": 0.5, "bitrate": 1500000, "path": path})
    stop = True; th.join()
    head = open(path, "rb").read(12) if os.path.exists(path) else b""
    print(f"{codec}/{transport}: {a.get('kbit_s')} kbit/s, {a.get('chunks')} chunks, first chunk {a.get('first_chunk_ms')} ms, engine CPU {a.get('engine_cpu_pct')}%, head {head[4:8] if transport=='fmp4' else head[:5].hex()} {a.get('error','')}", flush=True)
call(mover, {"op": "home"})
for p in (mover, streamer): p.stdin.close(); p.wait()
