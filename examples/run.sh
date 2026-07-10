#!/usr/bin/env bash
# curl equivalent of run.py: spawn a sandbox, upload app/analyze.py, exec it,
# then delete the sandbox. Run from your Mac (needs curl + jq).
#
# Usage: FORGEVM_URL=http://<ip>:7423 IMAGE=forgevm-python:latest ./run.sh
set -euo pipefail

BASE="${FORGEVM_URL:-http://localhost:7423}"
IMAGE="${IMAGE:-forgevm-python:latest}"
HERE="$(cd "$(dirname "$0")" && pwd)"

command -v jq >/dev/null || { echo "this script needs 'jq' (brew install jq)"; exit 1; }

echo "→ spawn sandbox  image=$IMAGE"
SPAWN=$(curl -sS -X POST "$BASE/api/v1/sandboxes" \
  -H 'Content-Type: application/json' -d "{\"image\":\"$IMAGE\"}")
echo "  $SPAWN"
ID=$(echo "$SPAWN" | jq -r .id)
[ "$ID" != "null" ] || { echo "spawn failed"; exit 1; }

cleanup() { echo "→ delete sandbox $ID"; curl -sS -X DELETE "$BASE/api/v1/sandboxes/$ID" || true; echo; }
trap cleanup EXIT

echo "→ upload /app/analyze.py"
CONTENT=$(jq -Rs . < "$HERE/app/analyze.py")   # JSON-encode the file (handles quotes/newlines)
curl -sS -X POST "$BASE/api/v1/sandboxes/$ID/files" \
  -H 'Content-Type: application/json' \
  -d "{\"path\":\"/app/analyze.py\",\"content\":$CONTENT}"; echo

echo "→ exec  python3 /app/analyze.py"
curl -sS -X POST "$BASE/api/v1/sandboxes/$ID/exec" \
  -H 'Content-Type: application/json' \
  -d '{"command":"python3 /app/analyze.py"}'; echo
