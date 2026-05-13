#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

SDC_FILE="$ROOT_DIR/syn_sta_rv32im_ahb_core/constraints/asap7_synth_cons.sdc"

WNS_FILE="$ROOT_DIR/syn_sta_rv32im_ahb_core/reports/timing/asap7_report_wns.rpt"

# ============================================================================
# ASAP7 Liberty Files
# ============================================================================

SIMPLE_LIB="$ROOT_DIR/syn_sta_rv32im_ahb_core/lib/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib"

SEQ_LIB="$ROOT_DIR/syn_sta_rv32im_ahb_core/lib/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib"

INVBUF_LIB="$ROOT_DIR/syn_sta_rv32im_ahb_core/lib/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib"

AO_LIB="$ROOT_DIR/syn_sta_rv32im_ahb_core/lib/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib"

# ============================================================================
# Sweep List (ns)
# ============================================================================

PERIODS=(0.06 0.05 0.045 0.04 0.035 0.03 0.025 0.02)

# ============================================================================
# Check SDC Exists
# ============================================================================

if [[ ! -f "$SDC_FILE" ]]; then
    echo "ERROR: Missing SDC file:"
    echo "$SDC_FILE"
    exit 1
fi

# ============================================================================
# Backup Original SDC
# ============================================================================

tmp_sdc_backup="$(mktemp)"

cp "$SDC_FILE" "$tmp_sdc_backup"

restore_sdc() {
    cp "$tmp_sdc_backup" "$SDC_FILE"
    rm -f "$tmp_sdc_backup"
}

trap restore_sdc EXIT

# ============================================================================
# Sweep Loop
# ============================================================================

best_period=""
best_wns=""

for p in "${PERIODS[@]}"; do

    half=$(awk -v v="$p" 'BEGIN { printf "%.3f", v/2.0 }')

    awk -v per="$p" -v half="$half" '
        /^create_clock -name clk/ {
            print "create_clock -name clk -period " per " -waveform {0 " half "} [get_ports Clk_In]"
            next
        }
        { print }
    ' "$tmp_sdc_backup" > "$SDC_FILE"

    echo ""
    echo "======================================================"
    echo "ASAP7 Sweep Period: ${p} ns"
    echo "======================================================"

    (
        cd "$ROOT_DIR"

        make synth_asap7 \
            > /tmp/asap7_synth.log 2>&1

        make sta_asap7 \
            > /tmp/asap7_sta.log 2>&1
            
    )

    if [[ ! -f "$WNS_FILE" ]]; then
        echo "ERROR: Missing WNS report:"
        echo "$WNS_FILE"
        exit 1
    fi

    wns=$(awk '
        /^[[:space:]]*wns/ {
            print $3
        }
    ' "$WNS_FILE" | tail -n 1)

    if [[ -z "$wns" ]]; then

        wns=$(grep -i "wns" "$WNS_FILE" | awk '{print $NF}' | tail -n 1 || true)

    fi

    if [[ -z "$wns" ]]; then
        echo "ERROR: Could not parse WNS."
        exit 1
    fi

    echo "WNS = $wns ns"

    if awk -v w="$wns" 'BEGIN { exit !(w >= 0.0) }'; then

        best_period="$p"
        best_wns="$wns"

    else

        echo ""
        echo "Timing failed at ${p} ns"
        break

    fi

done

# ============================================================================
# Final Result
# ============================================================================

echo ""

if [[ -n "$best_period" ]]; then

    fmax_ghz=$(awk -v p="$best_period" '
        BEGIN {
            printf "%.3f", 1.0/p
        }
    ')

    fmax_mhz=$(awk -v p="$best_period" '
        BEGIN {
            printf "%.2f", 1000.0/p
        }
    ')

    echo "======================================================"
    echo "Best Passing Period : ${best_period} ns"
    echo "Best WNS            : ${best_wns} ns"
    echo "Estimated Fmax      : ${fmax_ghz} GHz (${fmax_mhz} MHz)"
    echo "======================================================"

else

    echo "======================================================"
    echo "No passing timing point found."
    echo "======================================================"

fi