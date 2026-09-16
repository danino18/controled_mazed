#!/bin/sh
# Compiles the RTL listed in the Quartus project and runs self-checking
# testbenches in ModelSim-Intel ASE. Runs inside build/sim so that the
# lpm_rom models find their .mif files at the same relative paths as Quartus.
# Sources are passed as relative paths because the repository path has a space.
#
# Usage: sh sim/run_tests.sh [tb_name ...]          (default: every tb_*.sv except tb_render)
#        sh sim/run_tests.sh tb_render +shots=2,40      (writes build/sim/frame_NNN.png)

MODELSIM=${MODELSIM:-/c/intelFPGA_lite/17.0/modelsim_ase/win32aloem}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SIMDIR="$ROOT/build/sim"

mkdir -p "$SIMDIR"
cd "$SIMDIR" || exit 1
rm -rf work RTL
mkdir -p RTL
cp -r "$ROOT/fpga/RTL/MIF" RTL/ 2>/dev/null
cp -r "$ROOT/fpga/RTL/AUDIO" RTL/ 2>/dev/null   # melody_player_1's lpm_rom reads RTL/AUDIO/songs.mif
"$MODELSIM/vlib" work > /dev/null

# RTL sources in project order (packages first), excluding the board top level,
# the wrapper of the precompiled keyboard block, and supplied files that have a
# simulator-friendly copy in sim/models (see each file there).
SOURCES=$(grep -E "^set_global_assignment -name (SYSTEMVERILOG|VERILOG)_FILE RTL/" "$ROOT/fpga/controlled_maze.qsf" \
          | awk '{print $NF}' | grep -v "TOP/controlled_maze_top.sv" | grep -v "kbd_wrapper.v" \
          | grep -v "KEYBOARDX/random.sv" | grep -v "AUDIO/melody_player_1.sv" \
          | sed "s|^|../../fpga/|")

# shellcheck disable=SC2086
"$MODELSIM/vlog" -sv -quiet -work work ../../sim/models/*.sv $SOURCES ../../sim/tb_*.sv || exit 1

PLUSARGS=""
TESTS=""
for arg in "$@"; do
  case $arg in
    +*) PLUSARGS="$PLUSARGS $arg" ;;
    *)  TESTS="$TESTS $arg" ;;
  esac
done
if [ -z "$TESTS" ]; then
  TESTS=$(cd "$ROOT/sim" && ls tb_*.sv | sed 's/\.sv$//' | grep -v '^tb_render$')
fi

status=0
for tb in $TESTS; do
  # shellcheck disable=SC2086
  result=$("$MODELSIM/vsim" -c -quiet -L lpm_ver work."$tb" $PLUSARGS -do "run -all; quit -f" 2>&1)
  echo "$result" | grep -E "^# (PASS|FAIL|INFO|\*\* (Error|Fatal))" | sed 's/^# //'
  echo "$result" | grep -q "^# PASS: $tb" || status=1
done

for ppm in frame_*.ppm tour_*.ppm; do
  [ -f "$ppm" ] || continue
  perl "$ROOT/tools/ppm2png.pl" "$ppm" "${ppm%.ppm}.png"
done
exit $status
