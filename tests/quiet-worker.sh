#!/bin/bash
# CPU-busy but totally silent for ~8s — must NOT be treated as stalled.
python3 - <<'EOF'
import time
t = time.time() + 8
while time.time() < t:
    pass
print("done")
EOF
