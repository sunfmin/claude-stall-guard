#!/bin/bash
# Quiet 2s gaps between output — must NOT be treated as stalled (idle=5).
for i in 1 2 3; do
  echo "tick $i"
  sleep 2
done
echo "finished"
