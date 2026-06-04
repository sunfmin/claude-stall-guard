#!/bin/bash
# Simulates a package installer that asks for confirmation.
echo "fake-installer v1.0"
echo "Resolving dependencies..."
sleep 1
echo "Need to install 3 packages (12 MB)."
printf "Ok to proceed? (y/N) "
read -r answer
echo "answer=$answer"
echo "installed."
