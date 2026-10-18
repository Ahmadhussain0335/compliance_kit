#!/usr/bin/env sh
# Prints line coverage per file and in total for an lcov file.
# Usage: tool/coverage_summary.sh path/to/lcov.info
awk -F: '
  /^SF:/ { file=$2 }
  /^LF:/ { lf[file]=$2; tlf+=$2 }
  /^LH:/ { lh[file]=$2; tlh+=$2 }
  END {
    for (f in lf) printf "%6.2f%%  %s\n", (lf[f] ? 100*lh[f]/lf[f] : 100), f
    printf "TOTAL %.2f%% (%d/%d lines)\n", (tlf ? 100*tlh/tlf : 100), tlh, tlf
  }' "$1"
