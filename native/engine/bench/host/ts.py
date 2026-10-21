# Prefixes each line of stdin with the seconds since start.
import sys, time
t = time.time()
for line in sys.stdin:
    sys.stdout.write("%7.2f %s" % (time.time() - t, line))
    sys.stdout.flush()
