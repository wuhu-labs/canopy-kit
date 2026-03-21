#!/usr/bin/env python3
"""
Analyze an Instruments trace export.

Usage: analyze_trace.py --time-sample <xml> --binary <path> [--label <name>]
                        [--last-seconds <n>] [--interval-xml <xml>]
                        [--event-counts <file>]

Produces:
  - Library-level exclusive breakdown (from time-sample)
  - App-specific symbolicated inclusive/exclusive profile
  - Signpost interval and event summary
"""
import argparse
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict


# ---------------------------------------------------------------------------
# Time-sample parsing
# ---------------------------------------------------------------------------

def parse_time_samples(xml_path):
    tree = ET.parse(xml_path)
    root = tree.getroot()
    samples = []
    id_cache = {}

    for node in root.iter("node"):
        for row in node.findall("row"):
            time_el = row.find("sample-time")
            if time_el is None:
                continue
            if "ref" in time_el.attrib:
                ts_ns = id_cache.get(time_el.attrib["ref"], {}).get("ts_ns", 0)
            else:
                ts_ns = int(time_el.text)
                if "id" in time_el.attrib:
                    id_cache[time_el.attrib["id"]] = {"ts_ns": ts_ns}

            thread_el = row.find("thread")
            if thread_el is not None:
                if "ref" in thread_el.attrib:
                    thread_name = id_cache.get(thread_el.attrib["ref"], {}).get(
                        "thread_name", "Unknown"
                    )
                else:
                    thread_name = thread_el.attrib.get("fmt", "Unknown")
                    if "id" in thread_el.attrib:
                        id_cache[thread_el.attrib["id"]] = {
                            "thread_name": thread_name
                        }
            else:
                thread_name = "Unknown"

            state_el = row.find("thread-state")
            if state_el is not None:
                if "ref" in state_el.attrib:
                    state = id_cache.get(state_el.attrib["ref"], {}).get(
                        "state", "Unknown"
                    )
                else:
                    state = state_el.attrib.get("fmt", "Unknown")
                    if "id" in state_el.attrib:
                        id_cache[state_el.attrib["id"]] = {"state": state}
            else:
                state = "Unknown"

            bt_el = row.find("kperf-bt")
            addresses = []
            if bt_el is not None:
                if "ref" in bt_el.attrib:
                    addresses = id_cache.get(bt_el.attrib["ref"], {}).get(
                        "addresses", []
                    )
                else:
                    ta_el = bt_el.find("text-addresses")
                    if ta_el is not None and ta_el.text:
                        addresses = [
                            int(a) for a in ta_el.text.strip().split() if a != "0"
                        ]
                    if "id" in bt_el.attrib:
                        id_cache[bt_el.attrib["id"]] = {"addresses": addresses}

            samples.append(
                {
                    "ts_ns": ts_ns,
                    "thread": thread_name,
                    "state": state,
                    "addresses": addresses,
                }
            )
    return samples


def classify_address(addr):
    if addr < 0x180000000:
        return "app"
    if 0x18EC00000 <= addr < 0x190000000:
        return "CF/Foundation"
    if 0x190000000 <= addr < 0x195000000:
        return "AppKit"
    if 0x195000000 <= addr < 0x1A2000000:
        return "System/CG"
    if 0x1A2400000 <= addr < 0x1A3000000:
        return "AG/SwiftUI"
    if 0x1B3900000 <= addr < 0x1B4000000:
        return "Swift-stdlib"
    if 0x1C3300000 <= addr < 0x1CA000000:
        return "libswiftCore"
    if addr >= 0x200000000:
        return "libsystem/kernel"
    return "other"


def discover_app_range(samples, binary_path):
    out = subprocess.run(
        ["otool", "-l", binary_path], capture_output=True, text=True
    ).stdout
    vmsize = None
    in_text = False
    for line in out.splitlines():
        if "segname __TEXT" in line:
            in_text = True
        elif in_text and "vmsize" in line:
            vmsize = int(line.strip().split()[-1], 16)
            break
        elif in_text and "segname" in line:
            break

    if vmsize is None:
        vmsize = 0x200000

    app_addrs = set()
    for s in samples:
        for addr in s["addresses"]:
            if addr < 0x180000000 and addr > 0x100000000:
                app_addrs.add(addr)

    if not app_addrs:
        return None, None

    min_addr = min(app_addrs)
    load_addr = (min_addr >> 16) << 16
    end_addr = load_addr + vmsize

    return load_addr, end_addr


def symbolicate(binary_path, load_addr, addresses):
    if not addresses:
        return {}
    addr_strs = [f"0x{a:x}" for a in addresses]
    BATCH = 500
    mapping = {}
    for i in range(0, len(addr_strs), BATCH):
        batch = addr_strs[i : i + BATCH]
        batch_addrs = addresses[i : i + BATCH]
        result = subprocess.run(
            ["atos", "-o", binary_path, "-l", f"0x{load_addr:x}"] + batch,
            capture_output=True,
            text=True,
        )
        for addr, sym in zip(batch_addrs, result.stdout.strip().split("\n")):
            mapping[addr] = sym.strip()
    return mapping


def simplify_symbol(sym):
    if " (in " in sym:
        return sym.split(" (in ")[0]
    return sym


# ---------------------------------------------------------------------------
# Signpost interval XML parsing
# ---------------------------------------------------------------------------

def parse_interval_xml(xml_path):
    """Parse os-signpost-interval XML.

    Each row has: <string> (name), <duration> (with fmt like "2.84 ms"),
    <subsystem>, <category>, etc.
    """
    tree = ET.parse(xml_path)
    root = tree.getroot()
    id_cache = {}
    intervals = defaultdict(list)  # name -> [duration_ns, ...]

    for node in root.iter("node"):
        for row in node.findall("row"):
            # Resolve name from <string> element
            name = None
            duration_ns = None
            subsystem = None

            for child in row:
                tag = child.tag

                if "ref" in child.attrib:
                    cached = id_cache.get(child.attrib["ref"], {})
                    val = cached.get("fmt") or cached.get("text")
                else:
                    val = child.attrib.get("fmt") or child.text
                    if "id" in child.attrib:
                        id_cache[child.attrib["id"]] = {
                            "fmt": child.attrib.get("fmt"),
                            "text": child.text,
                        }

                if tag == "string":
                    name = val
                elif tag == "duration":
                    duration_ns = parse_duration(val)
                elif tag == "subsystem":
                    subsystem = val

            if name and duration_ns is not None:
                if subsystem and "canopykit" in subsystem.lower():
                    intervals[name].append(duration_ns)

    return intervals


def parse_duration(fmt_str):
    """Parse a duration string like '2.84 ms', '16.70 ms', '1.29 µs' to nanoseconds."""
    if not fmt_str:
        return None
    s = fmt_str.strip()
    try:
        if s.endswith(" ns"):
            return float(s[:-3])
        elif s.endswith(" µs"):
            return float(s[:-3]) * 1_000
        elif s.endswith(" ms"):
            return float(s[:-3]) * 1_000_000
        elif s.endswith(" s"):
            return float(s[:-2]) * 1_000_000_000
        else:
            return float(s)
    except ValueError:
        return None


def parse_event_counts(path):
    """Parse tab-separated event counts file: name\\tcount"""
    counts = {}
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split("\t")
                if len(parts) == 2:
                    counts[parts[0]] = int(parts[1])
    except (FileNotFoundError, ValueError):
        pass
    return counts


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Analyze Instruments trace exports")
    parser.add_argument("--time-sample", required=True, help="Time-sample XML path")
    parser.add_argument("--binary", required=True, help="App binary path")
    parser.add_argument("--label", default="trace", help="Label for the report")
    parser.add_argument("--last-seconds", type=float, default=5.0, help="Analyze last N seconds")
    parser.add_argument("--interval-xml", default=None, help="os-signpost-interval XML path")
    parser.add_argument("--event-counts", default=None, help="Event counts file path")
    args = parser.parse_args()

    # ---- Time-sample analysis ----
    samples = parse_time_samples(args.time_sample)
    if not samples:
        print("ERROR: No time samples found")
        sys.exit(1)

    all_ts = [s["ts_ns"] for s in samples]
    min_ts, max_ts = min(all_ts), max(all_ts)
    duration_s = (max_ts - min_ts) / 1e9

    cutoff_ns = max_ts - int(args.last_seconds * 1e9)
    tail = [
        s
        for s in samples
        if s["ts_ns"] >= cutoff_ns
        and "Main Thread" in s["thread"]
        and s["state"] == "Running"
    ]
    total = len(tail)

    print(f"{'=' * 80}")
    print(f"  {args.label}")
    print(f"{'=' * 80}")
    print(f"  Duration: {duration_s:.1f}s  |  Last {args.last_seconds}s main-thread running: {total} samples")
    print()

    # Library breakdown
    lib_counts = defaultdict(int)
    for s in tail:
        if s["addresses"]:
            lib_counts[classify_address(s["addresses"][0])] += 1

    libs = sorted(lib_counts.items(), key=lambda x: -x[1])
    print(f"  Library breakdown (exclusive, top-of-stack):")
    print(f"  {'Library':<22} {'Count':>6} {'%':>6}")
    print(f"  {'-' * 38}")
    for lib, count in libs:
        print(f"  {lib:<22} {count:>6} {count * 100.0 / total:>5.1f}%")
    print(f"  {'-' * 38}")
    print(f"  {'TOTAL':<22} {total:>6}")
    print()

    # App symbolication
    load_addr, end_addr = discover_app_range(samples, args.binary)
    if load_addr is None:
        print("  WARNING: Could not discover app address range")
    else:
        print(f"  App binary: load=0x{load_addr:x}  end=0x{end_addr:x}")

        all_app_addrs = set()
        for s in tail:
            for addr in s["addresses"]:
                if load_addr <= addr < end_addr:
                    all_app_addrs.add(addr)

        sym_map = symbolicate(args.binary, load_addr, sorted(all_app_addrs))

        inclusive = defaultdict(int)
        exclusive = defaultdict(int)

        for s in tail:
            seen = set()
            for i, addr in enumerate(s["addresses"]):
                if load_addr <= addr < end_addr:
                    sym = simplify_symbol(sym_map.get(addr, f"0x{addr:x}"))
                    if sym not in seen:
                        inclusive[sym] += 1
                        seen.add(sym)
                    if i == 0:
                        exclusive[sym] += 1

        print()
        print(f"  App INCLUSIVE (top 25):")
        print(f"  {'Count':>6} {'%':>6}  Function")
        print(f"  {'-' * 70}")
        for sym, count in sorted(inclusive.items(), key=lambda x: -x[1])[:25]:
            print(f"  {count:>6} {count * 100.0 / total:>5.1f}%  {sym}")

        print()
        print(f"  App EXCLUSIVE (top 25):")
        print(f"  {'Count':>6} {'%':>6}  Function")
        print(f"  {'-' * 70}")
        for sym, count in sorted(exclusive.items(), key=lambda x: -x[1])[:25]:
            print(f"  {count:>6} {count * 100.0 / total:>5.1f}%  {sym}")

    # Per-second timeline
    all_main = [
        s
        for s in samples
        if "Main Thread" in s["thread"] and s["state"] == "Running"
    ]
    print()
    print(f"  Main thread running samples per second:")
    print(f"  {'Sec':>4} {'Count':>6}")
    print(f"  {'-' * 14}")
    for sec in range(int(duration_s) + 1):
        lo = min_ts + int(sec * 1e9)
        hi = lo + int(1e9)
        count = sum(1 for s in all_main if lo <= s["ts_ns"] < hi)
        marker = " <-- analysis window" if lo >= cutoff_ns else ""
        print(f"  {sec:>3}s {count:>6}{marker}")

    # ---- Signpost analysis ----
    has_signposts = False

    if args.interval_xml:
        try:
            intervals = parse_interval_xml(args.interval_xml)
            if intervals:
                has_signposts = True
                print(f"\n  {'=' * 70}")
                print(f"  SIGNPOST INTERVALS (com.wuhu.canopykit)")
                print(f"  {'=' * 70}")
                print(f"\n  {'Name':<40} {'Count':>6} {'Mean':>10} {'Min':>10} {'Max':>10}")
                print(f"  {'-' * 80}")
                for name in sorted(intervals.keys()):
                    durations = intervals[name]
                    count = len(durations)
                    if count == 0:
                        continue
                    mean_us = sum(durations) / count / 1000
                    min_us = min(durations) / 1000
                    max_us = max(durations) / 1000
                    print(f"  {name:<40} {count:>6} {mean_us:>8.1f}µs {min_us:>8.1f}µs {max_us:>8.1f}µs")
        except Exception as e:
            print(f"\n  WARNING: Failed to parse interval XML: {e}", file=sys.stderr)

    if args.event_counts:
        events = parse_event_counts(args.event_counts)
        if events:
            has_signposts = True
            print(f"\n  {'=' * 70}")
            print(f"  SIGNPOST EVENTS (com.wuhu.canopykit)")
            print(f"  {'=' * 70}")
            print(f"\n  {'Name':<40} {'Count':>8}")
            print(f"  {'-' * 50}")
            for name, count in sorted(events.items(), key=lambda x: -x[1]):
                print(f"  {name:<40} {count:>8}")

    if not has_signposts:
        print(f"\n  (no signpost data found)")


if __name__ == "__main__":
    main()
