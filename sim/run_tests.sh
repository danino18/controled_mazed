#!/bin/sh
# Compiles the RTL and runs every self-checking testbench in ModelSim-Intel ASE.
# Usage: sh sim/run_tests.sh [tb_name ...]     (default: all tb_*.sv)

MODELSIM=${MODELSIM:-/c/intelFPGA_lite/17.0/modelsim_ase/win32aloem}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RTL="$ROOT/fpga/RTL"

cd "$ROOT/sim" || exit 1
rm -rf work
"$MODELSIM/vlib" work > /dev/null

"$MODELSIM/vlog" -sv -quiet -work work \
  "$RTL/PKG/palette_pkg.sv" \
  "$RTL/PKG/game_params_pkg.sv" \
  "$RTL/VGA/VGA_Controller.sv" \
  "$RTL/VGA/square_object.sv" \
  "$RTL/COMMON/"*.sv \
  "$RTL/DEBUG/"*.sv \
  "$RTL/DRAW/water_background.sv" \
  "$ROOT/sim/"tb_*.sv || exit 1

if [ $# -eq 0 ]; then
  set -- $(ls tb_*.sv | sed 's/\.sv$//')
fi

status=0
for tb in "$@"; do
  result=$("$MODELSIM/vsim" -c -quiet work."$tb" -do "run -all; quit -f" 2>&1 | grep -E "^# (PASS|FAIL|INFO)" | sed 's/^# //')
  echo "$result"
  echo "$result" | grep -q "^PASS: $tb" || status=1
done
exit $status
