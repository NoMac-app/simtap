# Summarizes the engine's JSON answers on stdin: one line per answer with a tree, a screenshot or an error.
import sys, json
for line in sys.stdin:
    try:
        a = json.loads(line)
    except Exception:
        continue
    if a.get("ready"):
        continue
    tree = a.get("tree")
    if tree:
        root = tree[0]
        labels = []
        def walk(n):
            if n.get("AXLabel") and len(labels) < 6:
                labels.append(n["AXLabel"])
            for c in n.get("children") or []:
                walk(c)
        for n in tree:
            walk(n)
        print("read %s ms: app %r, %d bytes, labels %s" % (a.get("ms"), root.get("AXLabel"), len(json.dumps(tree)), labels[1:6]))
    elif a.get("error"):
        print("error: %s" % a["error"])
    else:
        print("%s: %s ms" % (a.get("op", "answer"), a.get("ms")))
