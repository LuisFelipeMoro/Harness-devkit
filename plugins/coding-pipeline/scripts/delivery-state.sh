#!/usr/bin/env bash
# Resume state and the one status write for the thin orchestrator (agents/orchestrator.md).
#
# The orchestrator may not Read files, so the two facts it needs about a delivery
# come from here: the table row `| Status | ... |` and the story branches already
# merged into the delivery's release branch.
#
#   delivery-state.sh --key K                  print status row, file path, merged story branches
#   delivery-state.sh --key K --set VALUE      rewrite only the Status row; VALUE is one of the enum
#
# Exit codes: 0 ok · 1 refused (bad value, no single Status row) · 2 usage or delivery file not found.
set -u

STATUS_ENUM="Planning|In Progress|Blocked|Delivered"

usage() {
    echo "usage: delivery-state.sh --key K [--set \"$STATUS_ENUM\"]" >&2
    exit 2
}

key=""; value=""; set_mode=0
while [ $# -gt 0 ]; do
    case "$1" in
        --key) [ $# -ge 2 ] || usage; key="$2"; shift 2 ;;
        --set) [ $# -ge 2 ] || usage; value="$2"; set_mode=1; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$key" ] || usage
case "$key" in
    *[!A-Za-z0-9]*) echo "delivery-state: key must be alphanumeric: $key" >&2; exit 2 ;;
esac

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root" || exit 2

matches=$(ls docs/deliveries/delivery-*-"$key".md 2>/dev/null)
count=$(printf '%s' "$matches" | grep -c . || true)
if [ "$count" -ne 1 ]; then
    echo "delivery-state: expected one docs/deliveries/delivery-*-$key.md, found $count" >&2
    exit 2
fi
file="$matches"

if [ "$set_mode" -eq 1 ]; then
    case "$value" in
        Planning|"In Progress"|Blocked|Delivered) ;;
        *) echo "delivery-state: refused '$value' — status must be one of: $STATUS_ENUM" >&2; exit 1 ;;
    esac
    rows=$(grep -c '^| Status |' "$file" || true)
    if [ "$rows" -ne 1 ]; then
        echo "delivery-state: refused — $file has $rows Status rows, expected 1" >&2
        exit 1
    fi
    tmp="$file.tmp.$$"
    if ! awk -v v="$value" '/^\| Status \|/ { print "| Status | " v " |"; next } { print }' "$file" > "$tmp"; then
        rm -f "$tmp"
        echo "delivery-state: rewrite failed" >&2
        exit 1
    fi
    mv "$tmp" "$file"
    echo "status set: $value ($file)"
    exit 0
fi

grep -m1 '^| Status |' "$file" || { echo "delivery-state: no Status row in $file" >&2; exit 1; }
echo "path: $file"
for rel in $(git for-each-ref --format='%(refname:short)' "refs/heads/release/*-$key"); do
    git branch --merged "$rel" --list "feat/$key-*" --format="merged into $rel: %(refname:short)" 2>/dev/null
done | head -n 20
exit 0
