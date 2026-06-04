#!/bin/bash
# Simulates a credential prompt.
echo "connecting to example.com ..."
printf "Password: "
read -rs pw
echo
echo "authenticated."
