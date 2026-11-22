#!/bin/bash
# Copy the shared TC LMS iOS source from this (SG) repo into a country variant
# repo — tertiarycoursesmyapp (MY) or tertiarycoursesghapp (GH). Everything is
# shared except each repo's own Site.swift, project.yml, app icon, bundled
# Catalog.json, README/CHANGELOG and .env.
#
#   scripts/sync_variant.sh ../tertiarycoursesmyapp
set -euo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)"
dest="$(cd "${1:?usage: sync_variant.sh <variant-repo>}" && pwd)"
[ "$src" != "$dest" ] || { echo "refusing to sync onto itself"; exit 1; }
[ -f "$dest/TertiaryCoursesApp/Site.swift" ] || { echo "$dest has no TertiaryCoursesApp/Site.swift"; exit 1; }

# HARD RULE (22 Nov 2026): TC LMS is the non-WSQ app (C-prefix courses only). WSQ
# classes, SSG attendance and the TRAQOM survey belong to the TIA app. The API
# enforces the course filter (ai-mms scripts/audit/check-mobileapi-nonwsq.sh);
# this stops a WSQ-only feature being built into the apps.
"$src/scripts/check_nonwsq.sh" "$src/TertiaryCoursesApp" || exit 1

for f in "$src"/TertiaryCoursesApp/*.swift; do
    name=$(basename "$f")
    [ "$name" = "Site.swift" ] && continue
    cp "$f" "$dest/TertiaryCoursesApp/$name"
done
# Drop shared files that were deleted here.
for f in "$dest"/TertiaryCoursesApp/*.swift; do
    name=$(basename "$f")
    [ "$name" = "Site.swift" ] || [ -f "$src/TertiaryCoursesApp/$name" ] || rm -v "$f"
done
mkdir -p "$dest/scripts"
cp "$src/scripts/make_icon.swift" "$src/scripts/snapshot_catalog.sh" "$src/scripts/check_nonwsq.sh" "$dest/scripts/"
echo "synced shared source into $dest"
