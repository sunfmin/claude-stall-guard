#!/bin/bash
# Silent network worker: zero output, ~zero CPU, but steady loopback TCP
# traffic for ~8s. Simulates a slow download / long server round-trip.
# Must NOT be treated as a stall.
python3 - <<'EOF'
import socket, threading, time

srv = socket.socket()
srv.bind(('127.0.0.1', 0))
srv.listen(1)
port = srv.getsockname()[1]

def server():
    conn, _ = srv.accept()
    for _ in range(4):
        time.sleep(2)
        conn.sendall(b'x' * 2048)
    conn.close()

threading.Thread(target=server, daemon=True).start()
c = socket.socket()
c.connect(('127.0.0.1', port))
while c.recv(65536):
    pass
print('net-done')
EOF
