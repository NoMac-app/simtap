# Prints the reason and top frames of macOS/iOS .ips crash reports given as arguments.
import json, sys
for path in sys.argv[1:]:
    text = open(path).read()
    head, _, body = text.partition("\n")
    try:
        j = json.loads(body)
    except Exception as e:
        print(path, "unreadable", e); continue
    print("==", path.rsplit("/", 1)[-1], json.loads(head).get("timestamp"))
    print("  exception:", j.get("exception"), "| termination:", j.get("termination"))
    asi = j.get("asi")
    if asi: print("  asi:", asi)
    imgs = j.get("usedImages", [])
    th = [x for x in j.get("threads", []) if x.get("triggered")]
    for fr in (th[0]["frames"][:8] if th else []):
        i = fr.get("imageIndex")
        im = imgs[i] if i is not None and i < len(imgs) else {}
        print("    ", im.get("name"), fr.get("symbol"))
