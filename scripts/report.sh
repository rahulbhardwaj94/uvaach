#!/bin/bash
# Usage-quality report over REAL dictations (not synthetic fixtures).
# Reads ~/Library/Application Support/Vani/history.json — every dictation the
# app has pasted, with raw (Whisper output) vs final text, latency, and the
# vocabulary-correction count — plus regress.log for the nightly fixture WER.
#
#   ./scripts/report.sh          # daily trend, last 30 days
#   ./scripts/report.sh --all    # everything in history
set -euo pipefail

python3 - "$@" <<'PY'
import json, sys, datetime, collections, os

APP = os.path.expanduser("~/Library/Application Support/Vani")
REF = datetime.datetime(2001, 1, 1)   # Apple epoch
show_all = "--all" in sys.argv

try:
    entries = json.load(open(f"{APP}/history.json"))
except FileNotFoundError:
    sys.exit("no history.json yet — dictate something first")

for e in entries:
    e["when"] = REF + datetime.timedelta(seconds=e["date"])
entries.sort(key=lambda e: e["when"])
if not show_all:
    cutoff = datetime.datetime.now() - datetime.timedelta(days=30)
    entries = [e for e in entries if e["when"] >= cutoff]

# A quick short utterance right after another is usually the user repeating
# what Vani got wrong — the honest "it failed me" signal.
REDICTATION_GAP_S = 30
REDICTATION_MAX_WORDS = 6

days = collections.defaultdict(lambda: {
    "n": 0, "words": 0, "lat": [], "edited": 0, "with_raw": 0,
    "vocab_fixes": 0, "redictations": 0,
})
prev_when = None
for e in entries:
    d = days[e["when"].date()]
    words = len(e["text"].split())
    d["n"] += 1
    d["words"] += words
    if (p := e.get("processingSeconds")) is not None:
        d["lat"].append(p)
    if (raw := e.get("raw")) is not None:
        d["with_raw"] += 1
        if raw.strip() != e["text"].strip():
            d["edited"] += 1
    d["vocab_fixes"] += e.get("correctedWords") or 0
    if prev_when is not None and words <= REDICTATION_MAX_WORDS \
       and (e["when"] - prev_when).total_seconds() <= REDICTATION_GAP_S:
        d["redictations"] += 1
    prev_when = e["when"]

print(f"Vani usage report — {len(entries)} dictations, "
      f"{min(days)} → {max(days)}\n")
print(f"{'day':<12}{'dict':>5}{'words':>7}{'lat s':>7}"
      f"{'pipeline-edit':>15}{'vocab-fix':>11}{'re-dictated':>13}")
for day in sorted(days):
    d = days[day]
    lat = f"{sum(d['lat'])/len(d['lat']):.2f}" if d["lat"] else "-"
    edited = f"{100*d['edited']/d['with_raw']:.0f}%" if d["with_raw"] else "-"
    print(f"{day.isoformat():<12}{d['n']:>5}{d['words']:>7}{lat:>7}"
          f"{edited:>15}{d['vocab_fixes']:>11}{d['redictations']:>13}")

t = {k: sum(days[day][k] for day in days) for k in
     ("n", "words", "edited", "with_raw", "vocab_fixes", "redictations")}
lats = [x for day in days for x in days[day]["lat"]]
print(f"\ntotals: {t['n']} dictations, {t['words']} words"
      + (f", mean latency {sum(lats)/len(lats):.2f}s" if lats else ""))
if t["with_raw"]:
    print(f"pipeline edited raw Whisper output in "
          f"{100*t['edited']/t['with_raw']:.0f}% of dictations "
          f"({t['edited']}/{t['with_raw']} that recorded a raw)")
print(f"vocabulary rules fixed {t['vocab_fixes']} words; "
      f"{t['redictations']} quick re-dictations "
      f"(you repeating what it got wrong — lower is better)")

# What has been learned so far.
try:
    vocab = json.load(open(f"{APP}/vocabulary.json"))
    print(f"\nlearned vocabulary: {len(vocab)} rules")
    for r in vocab:
        print(f"  \"{r['find']}\" → \"{r['replace']}\"")
except FileNotFoundError:
    pass
try:
    sugg = json.load(open(f"{APP}/suggestions.json"))
    if sugg:
        print(f"pending auto-learned suggestions: "
              + ", ".join(f"\"{r['find']}\" → \"{r['replace']}\"" for r in sugg))
except FileNotFoundError:
    pass

# Nightly synthetic-fixture WER, for the code side of the ledger.
try:
    runs = []
    date = None
    for line in open(f"{APP}/regress.log"):
        if line.startswith("====="):
            date = line.strip("= \n")
        elif "mean WER" in line and date:
            runs.append((date, line.split("mean WER")[1].split("%")[0].strip()))
            date = None
    if runs:
        print("\nnightly fixture WER (code changes move this, usage doesn't):")
        for when, wer in runs[-10:]:
            print(f"  {when}  {wer}%")
except FileNotFoundError:
    pass
PY
