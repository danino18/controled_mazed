# Milestone Log

Measurements are from Quartus Prime Lite 17.0.0 Build 595, full compile (`quartus_sh --flow compile`), device 5CSXFC6D6F31C6 (41,910 ALMs, 5,662,720 memory bits, 553 M10K, 112 DSP).

| Milestone | Compile time | ALMs | Registers | Memory bits | M10K | DSP | Setup slack @31.5 MHz | Board check |
|---|---|---|---|---|---|---|---|---|
| M0 supplied `VGA_DEMO_Students` (unmodified) | 86 s | 787 (2%) | 592 | 2,555,904 (45%) | 312 (56%) | 0 | +17.39 ns (Fmax 69.7 MHz) | pending |
| M1 skeleton: water gradient, static bird box, FPS meter, codec held silent | 45 s | 90 (<1%) | 118 | 0 | 0 | 0 | +27.32 ns | passed (audio silent after fix) |

## M0 — Baseline of the supplied demo

Restore the reference copy (it is ignored by Git and can be regenerated):

```
cd reference
quartus_sh --restore -output vga_demo ../qar_files_from_labs/VGA_DEMO_Students.qar
cd vga_demo
quartus_sh --flow compile Lab1Demo
```

Findings:
- It compiles with 0 errors. The path contains a space (`controled mazed`), and neither restore nor compile had a problem with it.
- Memory use is dominated by `vga_bg.mif` (307,200 × 8 bits). This confirms the design decision to avoid a full-screen background ROM.
- The supplied `DE10_Standard_Audio.sdc` is a Terasic template. Two `create_generated_clock` lines are ignored (critical warnings) because their hierarchy paths do not exist, and it also references ports that the design does not have (`DRAM_*`, `VGA_CLK`, `AUD_BCLK`). The 31.5 MHz clock is still constrained through `derive_pll_clocks`. Our project will use a minimal, clean SDC instead.
- Nine debug outputs of the demo have no pin assignment (critical warning 169085). This is harmless in the demo.
- The keyboard block (`KBDINTF.qxp`) and the audio codec (`audio_codec_controller.QXP`) are precompiled netlists. Their ports, recovered from the demo schematics, are:
  - `KBDINTF(CLOCK_50, resetN, PS2_CLK, PS2_DAT → keyCode[8:0], make, break)`. `break` is a SystemVerilog keyword, so this block must be instantiated from a Verilog-2001 wrapper or with an escaped identifier.
  - `audio_codec_controller(CLOCK31_5, resetN, AUD_ADCLRCK, AUD_BCLK, dacdata_left[15:0], dacdata_right[15:0] → AUD_DACDAT, AUD_XCK, AUD_I2C_SCLK, adcdata_left/right; inout AUD_I2C_SDAT)`.
  - `CLK_31P5(refclk, rst → outclk_0, locked)`.

## M1 — Project skeleton

Build: `quartus_sh --flow compile controlled_maze` in `fpga/`. Tests: `sh sim/run_tests.sh`.

What is on screen:
- A water gradient: light aqua at the top, deep navy at the bottom, blended with a 4×4 ordered dither. It is purely procedural and uses no memory.
- A static amber 32×32 bird placeholder at x = 144, y = 224, drawn by the supplied `square_object`.
- HEX1..HEX0 show the measured frame rate (expected `72` or `73`); HEX5..HEX2 are blank.
- LEDs: LEDR0 = PLL locked, LEDR1 = logic out of reset, LEDR9 toggles every 32 frames (≈0.9 s period). Holding KEY0 resets the PLL and all logic.

Layout: `fpga/` mirrors the supplied project layout (`RTL/VGA`, `RTL/Seg7`, IP files at the project root). Supplied files are byte-identical copies. Project code lives in `RTL/PKG`, `RTL/COMMON`, `RTL/DRAW`, `RTL/DEBUG`, `RTL/TOP`, and SystemVerilog is used for the top level. Quartus's RTL Viewer provides the block diagram that the report needs.

Verification (ModelSim ASE, all pass):
- `tb_vga_timing`: the supplied `VGA_Controller` has a line period of 833 clocks and a frame period of **433,993 clocks = 72.582 frames/s**. `PixelX`/`PixelY` reach 640/480, one past the visible area. `fps_meter` reports `073`.
- `tb_bcd`: `bcd_counter` matches an integer model from 0 to 999, saturates at 999, and gives `clear` priority. `leading_zero_blank` is checked for every value.
- `tb_water`: every pixel of the 640×480 frame is a ramp colour, never `8'hFF`, and depth never gets brighter from one band to the next.
- The testbenches were checked against deliberately broken copies (a counter without saturation, a reversed ramp), and both failed as expected.

Findings that corrected the design (recorded in `DESIGN.md`):
- The colour format is **RRRGGGBB**, not 2-3-3 as first stated. Blue has 4 levels.
- The frame rate is 72.58 Hz rather than the 72.8 Hz estimate, because both counters run one step past their constant.
- Remaining warnings are expected: 13024/13410 for the HEX3–5 and LEDR2–8 outputs that are unused so far, and 15714 for default drive strength (the supplied project has the same warning). The 29 VGA outputs are not timing-constrained, exactly as in the supplied project.

Board check: program `fpga/output_files/controlled_maze.sof` with
`quartus_pgm -m jtag -o "p;fpga/output_files/controlled_maze.sof"`.

### M1 board validation (2026-09-16, DE10-Standard via `DE-SoC [USB-1]`, FPGA = JTAG device 2)

First build (checksum `0x00B25601`):
- Working: the monitor shows the aqua-to-navy gradient and the amber square; HEX1–HEX0 alternate between 72 and 73; LEDR9 blinks.
- Not OK: a repeating noise came from the audio output.

Cause:
- M1 has no audio logic. The synthesis hierarchy contains no codec controller, tone generator or melody player, and the top level has no audio ports.
- Quartus therefore left every codec pin as `RESERVED_INPUT_WITH_WEAK_PULLUP` (the default for unused pins).
- The supplied demo instead drives the codec's master clock `AUD_XCK` (AH30) and DAC data `AUD_DACDAT` (AF29) as outputs, and reads `AUD_BCLK` (AF30) and `AUD_ADCLRCK` (AH29) as inputs, because its codec runs in master mode.
- The WM8731 codec is a separate chip and keeps its I2C register settings when the FPGA is reprogrammed; only a board power cycle or an I2C reset clears them. If an audio design (such as the lab demo) configured it after power-on, it stays powered and unmuted. With its clock input floating next to fast video traces, it produced noise.
- The noise did not come from anything M1 generates, since M1 contains no audio logic.

Fix: `controlled_maze_top.sv` now declares `AUD_XCK` and `AUD_DACDAT` as outputs held at 0. The pins come from the new `audio_out` group in `tools/gen_pins.sh`, which uses the supplied `pin.tcl` numbers. The codec's other pins are unchanged:
- `AUD_BCLK`, `AUD_ADCLRCK`, `AUD_DACLRCK` and `AUD_ADCDAT` stay undriven, because in master mode the codec drives them.
- The I2C lines (Y24/Y23) are shared with the video-in decoder and are left alone.

This needed a recompile (45 s, 0 errors). The only new warnings are the two intended 13410 "stuck at GND" messages. The second build (checksum `0x00B27710`) was programmed and retested: the audio is silent, and the gradient, amber square, 72/73 display and LEDR9 are unchanged. **M1 board validation passed.**

Design rule: any build without the audio block must keep `AUD_XCK` and `AUD_DACDAT` driven low.
