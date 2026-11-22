#!/bin/bash
# HARD RULE (22 Nov 2026): TC LMS (SG / MY / GH) is the NON-WSQ app: C-prefix
# courses only. WSQ classes, SSG e-attendance and the TRAQOM survey belong to
# the TIA app. Fails when a WSQ-only feature appears in the app source.
# (Trainer qualification names such as "WSQ Advanced Certificate ... (ACLP)" are
# credentials, not WSQ course features, and are allowed.)
#
#   scripts/check_nonwsq.sh [source-dir]     exit 0 = clean, 1 = found
set -u
dir="${1:-$(cd "$(dirname "$0")/.." && pwd)/TertiaryCoursesApp}"
hits=$(grep -rniE 'traqom|tpgateway|skillsfuture|ssg[-_ ]?attendance|wsq' "$dir" \
        --include='*.swift' --include='*.kt' \
        | grep -viE 'non-wsq|TrainerBadge\(') || true
if [ -n "$hits" ]; then
    echo "$hits"
    echo "check_nonwsq: WSQ / SSG feature found above. TC LMS is non-WSQ (C-prefix) only." >&2
    exit 1
fi
echo "check_nonwsq: clean"
