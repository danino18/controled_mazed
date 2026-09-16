# Milestone Log

Measurements are from Quartus Prime Lite 17.0.0 Build 595, full compile (`quartus_sh --flow compile`), device 5CSXFC6D6F31C6 (41,910 ALMs, 5,662,720 memory bits, 553 M10K, 112 DSP).

| Milestone | Compile time | ALMs | Registers | Memory bits | M10K | DSP | Setup slack @31.5 MHz | Board check |
|---|---|---|---|---|---|---|---|---|
| M0 supplied `VGA_DEMO_Students` (unmodified) | 86 s | 787 (2%) | 592 | 2,555,904 (45%) | 312 (56%) | 0 | +17.39 ns (Fmax 69.7 MHz) | pending |
| M1 skeleton: water gradient, static bird box, FPS meter, codec held silent | 45 s | 90 (<1%) | 118 | 0 | 0 | 0 | +27.32 ns | passed (audio silent after fix) |
| M2 animated bird sprite, EASY sine trajectory | 51 s | 162 (<1%) | 178 | 24,576 | 4 | 0 | +24.646 ns | in M8 build |
| M3 scrolling coral column, geometric collision, freeze, sea floor | 61 s | 287 (<1%) | 264 | 57,344 | 8 | 0 | +24.51 ns (hold +0.17 ns) | in M8 build |
| M4 arrow-key maze control, playable single column | 71 s | 391 (<1%) | 357 | 57,344 | 8 | 0 | +22.47 ns (hold +0.17 ns) | in M8 build |
| M5 score + best score on VGA HUD and HEX | 74 s | 488 (1%) | 344 | 61,440 | 9 | 0 | +22.63 ns (hold +0.17 ns) | in M8 build |
| M6 game FSM, menus, GET READY, GAME OVER, restart, main menu, panels | 102 s* | 928 (2%) | 439 | 61,440 | 9 | 0 | +19.10 ns (hold +0.14 ns) | in M8 build |
| M7 1/2/3 columns verified; game logic separated into game_logic | 84 s | 931 (2%) | 435 | 61,440 | 9 | 0 | +18.23 ns (hold +0.16 ns) | in M8 build |

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

## M2 — Animated bird, EASY trajectory

- **Sprite:** `assets/sprites/bird.txt` is original 32×32 text pixel art with 3 wing-fin frames and 9 colours: amber body, cyan fin, navy outline. `tools/sprite_tool.tcl` (run with `quartus_sh -t`) converts it to `fpga/RTL/MIF/bird.mif` (3,072 × 8 bits) and to an HTML preview.
- **Drawing:** `bird_draw` is the supplied `square_object` (the bracket) plus the new `birdBitMap` (modelled on `smileyBitMap`). The ROM address is `{frame, y, x}`, and the frames play 0-1-2-1 at about 9 steps/s.
- **Layer latency:** every drawing layer delivers its colour 3 clocks after the pixel coordinates, and `water_background` was padded to match.
- **Game structure:**
  - `frame_sequencer` splits each frame into `tickMove` → `tickCheck` → `tickState`.
  - `game_system` holds everything that runs on the pixel clock and can be simulated. The board top keeps only the PLL, the reset and the codec tie-offs.
- **EASY motion:** `bird_trajectory` reuses the supplied `sintable` unchanged, so the bird bobs 96..351 px with a 256-frame period. The table's coarse steps give at most 4 px/frame.
- **Frame rendering:** `sim/tb_render.sv` records complete VGA frames from the `oVGA` pins (with board colour wiring), and `tools/ppm2png.pl` turns them into PNGs. The frames confirm the sprite is pixel-exact on screen.
- **Water ramp:** the deep water now stays royal blue (`00 00 BF`) instead of dropping into a teal-tinted dark band.
- **Test infrastructure:** `sim/run_tests.sh` runs in `build/sim` with the `lpm_ver` library. ROM instances use lower-case `lpm_*` parameter names, because the simulation model is case-sensitive.
- **Expected warnings:** 13049/13046 appear because `lpm_rom`'s internal tri-state outputs are converted to wires. The supplied demo shows the same warning 48 times.

## M3 — Coral column, collision, freeze

- **Coral art:** `assets/sprites/coral.txt` holds two original 64×32 tiles, a body and a tip, in 11 colours. The column is a stack of pink and violet colonies shaded like spheres lit from the upper left. The tip ends in antler branches with yellow polyps. `coral.mif` is 4,096 × 8 bits.
- **Coral state (logic only):** `obstacle_manager` keeps each column's position (1/64 px) and a random opening centre (176..303). All columns share one vertical offset. Columns re-enter 720 px to the right after leaving the screen, and a column scores when its collision core passes the bird. It already supports 1–3 columns; M3 uses 1.
- **Collision:** `collision_detect` is purely geometric. The bird hitbox is x 153..169 and y birdY+10..birdY+24. The coral core is 4 px narrower than the art on each side. The 8 rows of branch tips next to the opening never collide.
- **Coral drawing:** `coral_draw` counts tile rows from the opening edge, so the texture moves with the opening and the lower column is mirrored. One shared ROM serves every column, with a latency of 3 clocks.
- **Randomness:** `lfsr_rng` is a 16-bit Galois LFSR that steps once per frame; M8 adds seeding.
- **Sea floor:** a procedural wavy sand strip in `water_background` (sum of two triangle waves), with grain and pebbles.
- **Temporary round control:** in `game_system`, the round starts after reset and a collision freezes the world while the bird blinks.
- **Timing:** the new pipeline stages exposed a −0.051 ns hold violation, on a register-to-register path with 0.398 ns clock skew. `OPTIMIZE_HOLD_TIMING` is now `ALL PATHS` (the supplied project had it `OFF`), and timing is met in all four corners.
- **Tests:**
  - `tb_collision`: 11 hand-derived boundary cases plus 20,000 random layouts against a reference model.
  - `tb_obstacles`: 1, 2 and 3 columns over 1,500 frames each, checking movement, wrap-around, spacing, scoring, opening size and clamping, the shared offset, and the freeze.
  - `tb_water`: also checks the sand.
- **Renders:** the frames show the column scrolling, the opening, the sea floor, and the freeze at the point where the core reaches the hitbox.

## M4 — Arrow-key maze control

- **Keyboard block:** the supplied `KBDINTF.qxp` (from `VGA_DEMO_Students.qar`) is used as-is. It is clocked from the 31.5 MHz pixel clock, like the demo; the demo's timing report shows only the PLL clock domain. `kbd_wrapper.v` is plain Verilog because KBDINTF has an output named `break`, which is reserved in SystemVerilog.
- **Key decoding:** `key_input` uses four copies of the supplied `singleKeyDecoder` (unchanged, from `KBD09091201.qar`):
  - Arrow Up `9'h175` and Arrow Down `9'h172` give held levels for steering and press pulses for menus.
  - Enter `9'h05A` and keypad Enter `9'h15A` are combined into one confirm pulse.
- **Steering path:** `control_mux` (human/AI; the AI side is tied off) feeds `maze_control`. It holds the single shared vertical offset, clamped to ±224. While a key is held the speed ramps 1→2→3→4 px/frame every 4 frames, so taps give fine control. `MAZE_STEP_MAX` = 4 is at least the bird's top speed.
- **Restart:** Enter restarts the round after a collision (temporary until M6).
- **Tests:**
  - `tb_keys`: press pulses, held levels, auto-repeat, numpad 8/2 (same scan code without the E0 prefix) ignored, and both Enter keys.
  - `tb_maze`: the exact ramp sequence, clamping at both ends, no motion with both or neither key, the freeze, and restart.
- **Warnings (noise, not errors):**
  - `KBDINTF.qxp` carries the demo project's pin assignments. Quartus reports 36 × warning 15706 for demo nodes that don't exist here (`ADC_*`, `AUDOUT[*]`, `SW[*]`, …). Every node name shared with this design maps to the same pin.
  - Warning 12240 (imported black box) is disabled, as in `Lab1Demo.qsf`.

## M5 — Score, best score, HUD, seven-segment

- **Font:** `assets/fonts/font8x8.txt` is an original 8×8 bitmap font: 45 glyphs covering digits, A–Z and some punctuation, with 7×7 glyphs and bold 2-pixel stems. `tools/font_tool.tcl` turns it into `font.mif` (4,096 × 1 bit, address `{ASCII − 0x20, y, x}`).
- **Text table:** `text_pkg` lists every text line of every screen: position, scale ×2/×4/×8, visible screens, colour, and string. Dynamic lines show the score digits, the best-score digits, or the menu cursor (`>` plus gold highlight).
- **Renderer:** `text_draw` extends the supplied `NumbersBitMap` idea with a line → character → glyph-bit lookup, using shifts only and 3 clocks of latency.
- **Scores:** `score_bcd` keeps the current score (the M1 `bcd_counter`) and the best score in BCD. A new best is recorded only when strictly higher, and it survives restarts. HEX2..0 show the current score and HEX5..3 the best, with leading zeros blanked. The FPS display is no longer wired, but `fps_meter` stays in the project as a debug module.
- **Tests:**
  - `tb_score`: counting, carries, best-score rules, and reset.
  - `tb_text`:
    - Table checks: every string's length matches its declared length, every line fits on screen, and no two lines on the same screen overlap.
    - Rendering checks: digits, spaces, screen visibility, the cursor and highlight for all 9 cursor/item combinations, and NEW BEST shown only after a new best, blinking.
- **Bug caught by `tb_text`:** `cfg.scale + 2'd3` is a 2-bit expression, so 1 + 3 wrapped to 0 and every column index was wrong. The shift amount is now 3 bits wide.
- **Quartus 17 limitations found:**
  - It does not accept struct fields in `localparam` expressions, so the line table uses constant wires instead.
  - A comment that starts with the word "synthesis" is parsed as a synthesis attribute.

\* Compiled while a 4-minute simulation was running on the same PC.

## M6 — Complete game flow

- **`game_fsm`:** `MENU_DIFF → MENU_OBST → READY → PLAY → HIT → GAME_OVER → (RESTART → READY | MAIN MENU → MENU_DIFF)`.
  - Up/Down move a clamped cursor, and Enter confirms.
  - Menus reopen on the previous choice.
  - READY lasts 88 frames (~1.2 s) and HIT lasts 51 (~0.7 s).
  - GAME_OVER ignores Enter for 36 frames, so a key pressed during the crash cannot skip the score screen.
  - It emits one-clock `roundStart`, `roundOver` and `menuStart` pulses. The timers are parameters so testbenches can shorten them.
- **What runs in each screen:**
  - The coral scrolls only in PLAY.
  - The player can already steer the coral during GET READY.
  - The bird bobs (EASY motion) behind the menus, freezes after a crash, and blinks during HIT.
  - Coral is hidden in the menus.
- **`ui_panels`:** translucent navy panels (a one-pixel checkerboard) behind the menu, the GET READY text and the HUD, and a larger one behind GAME OVER. A navy bar with a cyan edge marks the selected entry, and a red checkerboard flash covers the screen for the first 8 frames of HIT.
- **LEDs:** LEDR[4:2] = screen, LEDR[6:5] = difficulty, LEDR[8:7] = column count (for board debugging).
- **Tests:**
  - `tb_game_fsm` (report module #1) visits every state and every transition: cursor clamping, remembered choices, exact timer lengths, pulses fired exactly once, the GAME OVER lockout, RESTART keeping the settings, MAIN MENU, and crash signals ignored outside PLAY.
  - `tb_render +scenario=tour` plays through all screens with scripted key presses and saves 8 screenshots (menu, obstacle menu, GET READY, play, hit flash, game over with each option selected, back to the menu).
- **Rendering note:** the menu and game-over panels need nearly 1,000 ALMs in total, mostly in the table-driven text renderer. That is still only 2% of the device.

## M7 — 1, 2 or 3 controlled columns

- The obstacle menu's choice drives `obstacle_manager`:
  - Columns are spaced 720 / count px apart (720, 360 or 240).
  - Every active column shares the one maze offset.
  - Collision and scoring cover every active column.
- **Refactor:** all game rules now live in `game_logic` (state machine, bird, steering, coral, collision, score), which knows nothing about pixels. `game_system` = VGA timing + keyboard + `game_logic` + drawing layers. This is the separation the design calls for, so the same rules can later be stepped by an on-chip training simulator.
- **`tb_autopilot` (new, headless):** runs `game_logic` with one frame every 6 clocks, which is thousands of frames per second, and plays it with a simple autopilot that holds Up/Down to keep the next opening centred on the bird.
  - For each column count it checks the menu selection, survival, and score = independently counted passes.
  - It also checks that every active opening moves exactly with the maze offset (10,845 column-frames confirmed), that the bird crashes when steering stops, and that RESTART and MAIN MENU work.
  - EASY results (2,500 frames each): 1 column scored 7, 2 columns 14, 3 columns 20. The autopilot never crashed.
- **`tb_collision`:** now also covers a crash caused by each column index, with 1–3 active columns, and inactive or distant columns never colliding.
- **`tb_obstacles`** already covers placement, spacing, scoring and clamping for 1, 2 and 3 columns.
