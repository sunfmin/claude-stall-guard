#!/bin/bash
# Simulates an npm-init style wizard prompt with a default value.
echo "This utility will walk you through creating a package.json file."
printf "package name: (demo) "
read -r name
echo "name=$name"
