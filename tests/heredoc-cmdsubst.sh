# A construct zsh and bash>=4 parse but macOS /bin/bash 3.2 rejects
# ("unexpected EOF while looking for matching `''"). Used to verify that
# stall-guard -c follows the session shell instead of forcing bash 3.2.
x="$(cat <<'EOF'
user's apostrophe and ` backtick
EOF
)"
echo "PARSED-OK: $x"
