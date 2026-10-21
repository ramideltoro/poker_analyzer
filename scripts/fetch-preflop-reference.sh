#!/bin/bash
set -euo pipefail
readerRaw="${1:?Supply a destination directory outside the source repository}"
readerProject="$(cd "$(dirname "$0")/.." && pwd)"
readerCommit=f4c46143a6f4504f2b2fe82da88dadec84f1c46a
mkdir -p "$readerRaw"
curl -fL --retry 2 "https://raw.githubusercontent.com/oscar6echo/Poker2/$readerCommit/Tables/df_preflop_hand_distrib.csv" -o "$readerRaw/preflop-category.csv"
ruby "$readerProject/scripts/import-preflop-reference.rb" "$readerRaw"
