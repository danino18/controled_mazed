#!/bin/sh
# Emits Quartus pin assignments (DE10-Standard) for the top-level ports that exist
# in the current milestone. Pin numbers are copied from the supplied lab file
# qar_files_from_labs/VGA_DEMO_Students.qar : constraints/pin.tcl.
# Usage: tools/gen_pins.sh GROUP... >> fpga/controlled_maze.qsf

pin() {
  echo "set_location_assignment PIN_$2 -to $1"
  echo "set_instance_assignment -name IO_STANDARD \"3.3-V LVTTL\" -to $1"
}

bus() {  # bus NAME PIN0 PIN1 ...
  name=$1; shift; i=0
  for p in "$@"; do pin "$name[$i]" "$p"; i=$((i+1)); done
}

for group in "$@"; do
  echo "# ---- $group"
  case $group in
    clock) pin CLOCK_50 AF14 ;;
    reset) pin resetN_pin AJ4 ;;
    keys)  bus KEY X AK4 AA14 AA15 | grep -v "KEY\[0\]" ;;
    sw)    bus SW AB30 Y27 AB28 AC30 W25 V25 AC28 AD30 AC29 AA30 ;;
    ledr)  bus LEDR AA24 AB23 AC23 AD24 AG25 AF25 AE24 AF24 AB22 AC22 ;;
    hex)
      bus HEX0 W17  V18  AG17 AG16 AH17 AG18 AH18
      bus HEX1 AF16 V16  AE16 AD17 AE18 AE17 V17
      bus HEX2 AA21 AB17 AA18 Y17  Y18  AF18 W16
      bus HEX3 Y19  W19  AD19 AA20 AC20 AA19 AD20
      bus HEX4 AD21 AG22 AE22 AE23 AG23 AF23 AH22
      bus HEX5 AF21 AG21 AF20 AG20 AE19 AF19 AB21 ;;
    vga)
      # [7:0] VGA_R, [15:8] VGA_G, [23:16] VGA_B, [24] HS, [25] VS, [26] SYNC_N, [27] BLANK_N, [28] VGA_CLK
      bus OVGA AK29 AK28 AK27 AJ27 AH27 AF26 AG26 AJ26 \
               AK26 AJ25 AH25 AK24 AJ24 AH24 AK23 AH23 \
               AJ21 AJ20 AH20 AJ19 AH19 AJ17 AJ16 AK16 \
               AK19 AK18 AJ22 AK22 AK21 ;;
    ps2)   pin PS2_CLK AB25; pin PS2_DAT AA25 ;;
    sw0)   pin SW0 AB30 ;;
    # Full WM8731-class codec I/O (supplied pin.tcl): AUDIN[1]=ADCLRCK,
    # AUDIN[2]=BCLK (codec drives these); AUDOUT[4]=DACDAT, AUDOUT[5]=XCK,
    # AUDOUT[6]=I2C_SCLK, AUDOUT[7]=I2C_SDAT (FPGA drives/shares these).
    audio)
      pin AUD_ADCLRCK AH29
      pin AUD_BCLK AF30
      pin AUD_DACDAT AF29
      pin AUD_XCK AH30
      pin AUD_I2C_SCLK Y24
      pin AUD_I2C_SDAT Y23 ;;
    *) echo "unknown group $group" >&2; exit 1 ;;
  esac
done
