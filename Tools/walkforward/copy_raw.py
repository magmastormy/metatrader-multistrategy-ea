import os, sys, time

src = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\FB9A56D617EDDDFE29EE54EBEFFE96C1\MQL5\Files\AITraining_Enterprise_H1.csv"
dst = r"D:\TraeProjects\metatrader-multistrategy-ea\Tools\walkforward\AITraining_Enterprise_H1.csv"

print("src exists:", os.path.exists(src))
if os.path.exists(src):
    print("src size_mb: %.1f" % (os.path.getsize(src) / 1e6))

t0 = time.time()
mode = "normal"
try:
    with open(src, "rb") as f, open(dst, "wb") as g:
        while True:
            chunk = f.read(8 * 1024 * 1024)
            if not chunk:
                break
            g.write(chunk)
except Exception as e1:
    mode = "rawfd"
    print("normal copy failed:", repr(e1))
    fd = os.open(src, os.O_RDONLY | os.O_BINARY)
    try:
        with open(dst, "wb") as g:
            while True:
                chunk = os.read(fd, 8 * 1024 * 1024)
                if not chunk:
                    break
                g.write(chunk)
    finally:
        os.close(fd)

print("copied via", mode, "in %.1fs" % (time.time() - t0))
print("dst size_mb: %.1f" % (os.path.getsize(dst) / 1e6))
