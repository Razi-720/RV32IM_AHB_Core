#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SDC_FILE="$ROOT_DIR/syn_sta_rv32im_ahb_core/constraints/synthesis_constraints.sdc"
WNS_FILE="$ROOT_DIR/syn_sta_rv32im_ahb_core/reports/timing/report_wns.rpt"
LIB_FLAVOR="${LIB_FLAVOR:-hd}"
LIB_FILE="${LIB_FILE:-}"

find_lib_for_flavor() {
  local flavor="$1"
  local p

  for p in \
    "/foss/pdks/sky130A/libs.ref/sky130_fd_sc_${flavor}/lib/sky130_fd_sc_${flavor}__tt_025C_1v80.lib" \
    "/foss/pdks/sky130A/libs.ref/sky130_fd_sc_${flavor}/timing/sky130_fd_sc_${flavor}__tt_025C_1v80.lib"; do
    [[ -f "$p" ]] && { echo "$p"; return 0; }
  done

  if [[ -d /foss/pdks ]]; then
    p="$(find /foss/pdks -type f -name "sky130_fd_sc_${flavor}__*tt*1v80*.lib" 2>/dev/null | head -n 1 || true)"
    [[ -n "$p" ]] && { echo "$p"; return 0; }
  fi

  return 1
}

if [[ -z "$LIB_FILE" ]]; then
  LIB_FILE="$(find_lib_for_flavor "$LIB_FLAVOR" || true)"

  # If HS is not installed, transparently fall back to HD.
  if [[ -z "$LIB_FILE" && "$LIB_FLAVOR" == "hs" ]]; then
    echo "WARNING: HS library not found. Falling back to HD library."
    LIB_FLAVOR="hd"
    LIB_FILE="$(find_lib_for_flavor "$LIB_FLAVOR" || true)"
  fi
fi

if [[ -z "$LIB_FILE" ]]; then
  echo "ERROR: Could not locate liberty file for LIB_FLAVOR=${LIB_FLAVOR}."
  exit 1
fi

echo "Using liberty: $LIB_FILE"

# Coarse-to-fine sweep (ns): from easy to aggressive.
PERIODS=(20 18 16 14 12 10 9 8 7 6 5 4 3)

if [[ ! -f "$SDC_FILE" ]]; then
  echo "ERROR: SDC file not found: $SDC_FILE"
  exit 1
fi

tmp_sdc_backup="$(mktemp)"
cp "$SDC_FILE" "$tmp_sdc_backup"
restore_sdc() {
  cp "$tmp_sdc_backup" "$SDC_FILE"
  rm -f "$tmp_sdc_backup"
}
trap restore_sdc EXIT

best_period=""
best_wns=""

for p in "${PERIODS[@]}"; do
  half=$(awk -v v="$p" 'BEGIN { printf "%.3f", v/2.0 }')

  awk -v per="$p" -v half="$half" '
    /^create_clock -name clk -period/ {
      print "create_clock -name clk -period " per " -waveform {0 " half "} [get_ports Clk_In]"
      next
    }
    { print }
  ' "$tmp_sdc_backup" > "$SDC_FILE"

  echo "=== Sweep period: ${p} ns (LIB_FLAVOR=${LIB_FLAVOR}) ==="
  (cd "$ROOT_DIR" && make LIB_FLAVOR="$LIB_FLAVOR" LIB_FILE="$LIB_FILE" synth >/dev/null && make LIB_FLAVOR="$LIB_FLAVOR" LIB_FILE="$LIB_FILE" sta >/dev/null)

  if [[ ! -f "$WNS_FILE" ]]; then
    echo "ERROR: Missing WNS report: $WNS_FILE"
    exit 1
  fi

  wns=$(awk '/wns max/ { print $3 }' "$WNS_FILE" | tail -n 1)
  if [[ -z "$wns" ]]; then
    echo "ERROR: Could not parse WNS from $WNS_FILE"
    exit 1
  fi

  echo "WNS = $wns ns"

  if awk -v w="$wns" 'BEGIN { exit !(w >= 0.0) }'; then
    best_period="$p"
    best_wns="$wns"
  else
    break
  fi

done

if [[ -n "$best_period" ]]; then
  fmax_mhz=$(awk -v p="$best_period" 'BEGIN { printf "%.2f", 1000.0/p }')
  echo ""
  echo "Best passing period: ${best_period} ns (WNS ${best_wns} ns)"
  echo "Estimated Fmax: ${fmax_mhz} MHz"
else
  echo ""
  echo "No passing period found in sweep list."
fi
