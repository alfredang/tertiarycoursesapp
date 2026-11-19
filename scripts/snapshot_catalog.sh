#!/bin/bash
# Refresh the bundled offline catalog (TertiaryCoursesApp/Catalog.json) from this
# app's site. The app always prefers the live /mobileapi/catalog feed; this
# snapshot is only the first-launch / offline floor.
#   scripts/snapshot_catalog.sh [base-url]
set -euo pipefail
cd "$(dirname "$0")/.."
BASE="${1:-$(sed -n 's/.*baseURL = URL(string: "\(.*\)")!/\1/p' TertiaryCoursesApp/Site.swift)}"
tmp=$(mktemp)
curl -fsS --max-time 120 "$BASE/mobileapi/catalog" -o "$tmp"
python3 - "$tmp" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("ok") and len(d["courses"]) >= 20, "catalog looks truncated: %r" % d.get("count")
json.dump({"courses": d["courses"]}, open("TertiaryCoursesApp/Catalog.json", "w"), ensure_ascii=False, separators=(",", ":"))
print("Catalog.json:", len(d["courses"]), "courses")
PY
rm -f "$tmp"
