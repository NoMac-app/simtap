# T16's host side: the cost of a sync manifest for a source tree (path, size, mtime, and optionally a SHA-256), the
# bytes of the manifest, and what one changed file means. Usage: manifest.py <dir>
import hashlib, json, os, sys, time, zlib
root = sys.argv[1]
def walk():
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in (".git", "node_modules", "DerivedData", ".build", "Pods", "build")]
        for f in files: yield os.path.join(d, f)
t = time.time(); stats = [(p, os.stat(p)) for p in walk()]; t_stat = time.time() - t
size = sum(s.st_size for _, s in stats)
t = time.time(); hashes = {}
for p, s in stats:
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""): h.update(chunk)
    hashes[p] = h.hexdigest()
t_hash = time.time() - t
manifest = json.dumps([[os.path.relpath(p, root), s.st_size, int(s.st_mtime), hashes[p]] for p, s in stats]).encode()
print(f"{len(stats)} files, {size / 1e6:.1f} MB; stat-only manifest {t_stat * 1000:.0f} ms; with SHA-256 {t_hash:.2f} s; manifest {len(manifest) / 1e3:.0f} KB, {len(zlib.compress(manifest, 6)) / 1e3:.0f} KB compressed")
