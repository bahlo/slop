#!/bin/bash
# Headless smoke test: selftest (works in any session) + a short live launch
# (needs a GUI session, i.e. a logged-in Mac — not bare SSH/CI).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
BIN=.build/debug/Tomato

echo "--- selftest"
output=$("$BIN" --selftest)
[[ "$output" == *"SELFTEST OK"* ]] || { echo "FAIL: selftest output: $output"; exit 1; }
echo "$output"

echo "--- live launch (4s survival)"
DATA_DIR=$(mktemp -d)
trap 'rm -rf "$DATA_DIR"' EXIT
TOMATO_DATA_DIR="$DATA_DIR" "$BIN" &
PID=$!
sleep 4
kill -0 "$PID" 2>/dev/null || { echo "FAIL: app exited early"; exit 1; }
kill "$PID"
wait "$PID" 2>/dev/null || true
echo "live launch OK"

echo "--- break-panel launch (reminder fires during 8s window)"
PANEL_DIR=$(mktemp -d)
trap 'rm -rf "$DATA_DIR" "$PANEL_DIR"' EXIT
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$PANEL_DIR/entries.json" <<EOF
{"version":1,"entries":[{"id":"11111111-2222-3333-4444-555555555555","start":"$NOW"}]}
EOF
cat > "$PANEL_DIR/settings.json" <<'EOF'
{"workInterval":2,"breakDuration":2,"snoozeInterval":2}
EOF
TOMATO_DATA_DIR="$PANEL_DIR" "$BIN" &
PID=$!
sleep 8
kill -0 "$PID" 2>/dev/null || { echo "FAIL: app died while showing break panel"; exit 1; }
kill "$PID"
wait "$PID" 2>/dev/null || true
echo "break-panel launch OK"

echo "--- app bundle"
make app
codesign --verify --deep dist/Tomato.app
BUNDLE_BIN=dist/Tomato.app/Contents/MacOS/Tomato
output=$("$BUNDLE_BIN" --selftest)
[[ "$output" == *"SELFTEST OK"* ]] || { echo "FAIL: bundle selftest: $output"; exit 1; }
BUNDLE_DIR=$(mktemp -d)
trap 'rm -rf "$DATA_DIR" "$PANEL_DIR" "$BUNDLE_DIR"' EXIT
TOMATO_DATA_DIR="$BUNDLE_DIR" "$BUNDLE_BIN" &
PID=$!
sleep 4
kill -0 "$PID" 2>/dev/null || { echo "FAIL: bundled app exited early"; exit 1; }
kill "$PID"
wait "$PID" 2>/dev/null || true
echo "app bundle OK"

echo "SMOKE OK"
