#!/bin/bash
# A prompt that stdin-EOF can NOT resolve: prints a y/N question, then
# blocks reading an fd that never delivers — like a tool waiting on a
# side channel instead of stdin. Must be detected as a stall.
echo "fake-installer v2 (EOF-immune)"
printf "Ok to proceed? (y/N) "
read -r answer < <(sleep 300)
echo "answer=$answer"
