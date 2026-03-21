#!/bin/bash
set -euo pipefail

LABEL="${1:-$(date +%Y%m%d-%H%M%S)}"
WORKSPACE="CanopyKit.xcworkspace"
SCHEME="CanopyKitDemo"
CONFIG="Release"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BENCH_DIR="$ROOT_DIR/Benchmarks"
TRACE_PATH="$BENCH_DIR/${LABEL}.trace"
TIME_SAMPLE_XML="$BENCH_DIR/${LABEL}-time-sample.xml"
INTERVAL_XML="$BENCH_DIR/${LABEL}-os-signpost-interval.xml"
REPORT_PATH="$BENCH_DIR/${LABEL}-report.txt"

mkdir -p "$BENCH_DIR"

cd "$ROOT_DIR"

# --- Step 1: Build ---
echo "==> Building $SCHEME ($CONFIG)..."
xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIG" \
  build -quiet 2>&1

# --- Step 2: Discover product path ---
BUILT_PRODUCTS_DIR=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIG" \
  -showBuildSettings 2>/dev/null | grep '^\s*BUILT_PRODUCTS_DIR' | awk '{print $3}')
PRODUCT_NAME=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIG" \
  -showBuildSettings 2>/dev/null | grep '^\s*FULL_PRODUCT_NAME' | awk '{print $3}')
APP_PATH="$BUILT_PRODUCTS_DIR/$PRODUCT_NAME"
BINARY_PATH="$APP_PATH/Contents/MacOS/CanopyKitDemo"

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: App not found at $APP_PATH"
  exit 1
fi
echo "    App: $APP_PATH"

# --- Step 3: Launch app and record trace (Time Profiler + os_signpost) ---
echo "==> Launching app and recording trace..."
rm -rf "$TRACE_PATH"

open "$APP_PATH"
sleep 1
PID=$(pgrep -n CanopyKitDemo)
echo "    PID: $PID"

xctrace record \
  --template 'Time Profiler' \
  --instrument 'os_signpost' \
  --output "$TRACE_PATH" \
  --time-limit 7s \
  --attach "$PID" 2>&1 || true

if [ ! -d "$TRACE_PATH" ]; then
  echo "ERROR: Trace not created at $TRACE_PATH"
  exit 1
fi
echo "    Trace: $TRACE_PATH"

# --- Step 4: Export time-sample XML ---
echo "==> Exporting time-sample data..."
xctrace export \
  --input "$TRACE_PATH" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-sample"]' \
  --output "$TIME_SAMPLE_XML" 2>&1

if [ ! -s "$TIME_SAMPLE_XML" ]; then
  echo "WARNING: time-sample export produced empty file"
fi
echo "    Time sample XML: $TIME_SAMPLE_XML ($(wc -c < "$TIME_SAMPLE_XML" | tr -d ' ') bytes)"

# --- Step 5: Export signpost interval data ---
echo "==> Exporting signpost interval data..."
xctrace export \
  --input "$TRACE_PATH" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost-interval"]' \
  --output "$INTERVAL_XML" 2>&1 || true

if [ -s "$INTERVAL_XML" ]; then
  echo "    Interval XML: $INTERVAL_XML ($(wc -c < "$INTERVAL_XML" | tr -d ' ') bytes)"
else
  echo "    WARNING: No signpost interval data"
fi

# --- Step 6: Stream-count signpost events (avoid 300MB+ XML export) ---
echo "==> Counting signpost events (streaming)..."
EVENT_COUNTS_FILE="$BENCH_DIR/${LABEL}-event-counts.txt"

# Export raw os-signpost to stdout and pipe through a streaming counter.
# The XML uses id/ref dedup: <signpost-name id="30" fmt="resolvedNodeCreated">
# appears once, then subsequent rows use <signpost-name ref="30"/>.
# We build an id->name map, then count rows that are Event type with our names.
xctrace export \
  --input "$TRACE_PATH" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]' 2>/dev/null \
  | python3 -c "
import sys, re
from collections import Counter

our_events = {
    'bodyEvaluated', 'componentCreated', 'componentRemoved',
    'resolvedNodeCreated', 'resolvedNodeReused',
    'sizeCacheHit', 'sizeCacheMiss',
    'renderNodeReused', 'renderNodeCreated',
}

# Map signpost-name id -> name
name_by_id = {}
# Map event-type id -> type string
etype_by_id = {}

counts = Counter()

# Patterns
name_def = re.compile(r'<signpost-name id=\"(\d+)\" fmt=\"([^\"]+)\">')
name_ref = re.compile(r'<signpost-name ref=\"(\d+)\"/>')
etype_def = re.compile(r'<event-type id=\"(\d+)\" fmt=\"([^\"]+)\">')
etype_ref = re.compile(r'<event-type ref=\"(\d+)\"/>')

for line in sys.stdin:
    if '<row>' not in line:
        continue

    # Learn definitions
    for m in name_def.finditer(line):
        name_by_id[m.group(1)] = m.group(2)
    for m in etype_def.finditer(line):
        etype_by_id[m.group(1)] = m.group(2)

    # Determine event type for this row
    is_event = False
    em = etype_def.search(line)
    if em:
        is_event = em.group(2) == 'Event'
    else:
        em = etype_ref.search(line)
        if em:
            is_event = etype_by_id.get(em.group(1)) == 'Event'

    if not is_event:
        continue

    # Determine signpost name for this row
    nm = name_def.search(line)
    if nm:
        name = nm.group(2)
    else:
        nm = name_ref.search(line)
        if nm:
            name = name_by_id.get(nm.group(1))
        else:
            continue

    if name in our_events:
        counts[name] += 1

for name, count in sorted(counts.items(), key=lambda x: -x[1]):
    print(f'{name}\t{count}')
" > "$EVENT_COUNTS_FILE" 2>/dev/null || true

if [ -s "$EVENT_COUNTS_FILE" ]; then
  echo "    Event counts:"
  while IFS=$'\t' read -r name count; do
    printf "      %-40s %s\n" "$name" "$count"
  done < "$EVENT_COUNTS_FILE"
else
  echo "    WARNING: No event counts extracted"
fi

# --- Step 7: Analyze ---
echo "==> Analyzing..."
python3 "$SCRIPT_DIR/analyze_trace.py" \
  --time-sample "$TIME_SAMPLE_XML" \
  --binary "$BINARY_PATH" \
  --label "$LABEL" \
  --interval-xml "$INTERVAL_XML" \
  --event-counts "$EVENT_COUNTS_FILE" \
  | tee "$REPORT_PATH"

echo ""
echo "==> Done. Report: $REPORT_PATH"
