# Milestone Log

Measurements are from Quartus Prime Lite 17.0.0 Build 595, full compile (`quartus_sh --flow compile`), project device setting 5CSXFC6D6F31C6 (41,910 ALMs, 5,662,720 memory bits, 553 M10K, 112 DSP). The board chip reports JTAG IDCODE 02D020DD (Cyclone V SoC A6/C6 die), which has the same fabric; see M9, D1.

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
| M8 MEDIUM + HARD bird motion, seeded leap-forward LFSRs | 95 s | 1,125 (3%) | 526 | 61,440 | 9 | 0 | +11.87 ns (hold +0.17 ns) | in M8 build |
| M8+ audio (score/fail sounds), Numpad 4/6 world speed (commit `2a77c15`) | not recorded | 1,352 (3%) | 809 | 71,680 | 11 | 0 | +11.18 ns (hold +0.118 ns) | reported working by the team |
| M9 world/lane split, fixed-point network, text screens, mode menu, WATCH AI (demo network), KEY1/SW1 | 95 s | 2,051 (5%) | 1,507 | 418,048 (7%) | 66 (12%) | 4 | +11.30 ns (hold +0.122 ns) | passed (reported by the user, 2026-09-17) |
| M10 8 real parallel training lanes, throttle, batch scheduler (fixed population), snapshot, training screen | 221 s | 6,591 (16%) | 6,319 | 507,648 (9%) | 78 (14%) | 14 | +10.43 ns (hold +0.113 ns) | not programmed (M12 board test) |
| M11 genetic algorithm, validation, champion, final test, learning chart, commit to WATCH AI, JTAG probe | 230 s | 7,165 (17%) | 7,144 | 545,280 (10%) | 85 (15%) | 16 | +9.03 ns (hold +0.093 ns) | programmed; training measured over JTAG |
| M12 complete product: no demo network, pause menu (KEEP / DISCARD), TRAINING COMPLETE with TRAIN AGAIN, completion sound, AI status, clean final compile | 277 s | 7,225 (17%) | 7,118 | 652,288 (12%) | 96 (17%) | 16 | +10.56 ns system clock, +9.03 ns JTAG (hold +0.121 ns) | final build programmed; training measured over JTAG; physical test by the user pending |

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

## M8 — Three real difficulty levels

Only the trajectory generator changes between difficulties (`bird_trajectory`); drawing and collision are shared.

- **EASY:** a sine bob from the supplied `sintable`. It is exactly periodic (256 frames) and ranges 96..351 px at ≤ 4 px/frame.
- **MEDIUM:** a random up/down decision every 24 frames. Speed eases (16/64 px per frame²) towards ±2.5 px/frame, and the bird always turns away within 48 px of the top or bottom.
- **HARD:** chases a random target height, closing 1/8 of the distance per frame. A new target arrives after a random 6..37 frames, so there is no fixed rhythm. Speed is capped at 3.75 px/frame and acceleration at 0.5 px/frame², plus ±1/16 px of jitter. Both limits stay within the player's 4 px/frame maze speed.
- **Randomness:**
  - The supplied `random.sv` (unchanged) latches a free-running counter on every Enter press, and that value seeds two LFSRs (coral, bird) at the start of each round.
  - `lfsr_rng` now leaps 16 steps per frame, so each frame gets 16 fresh bits. The full 65,535 period is kept and checked by `tb_lfsr`.
  - Simulation uses `sim/models/random.sv`, a copy of the supplied file with only the parameter declarations moved, because ModelSim rejects the original's use of a parameter before its declaration.
- **`tb_bird` (report module #2)** runs 3,000 frames per mode, using the real LFSR, and checks bounds, per-frame movement, speed and acceleration limits, and decision timing.
  - Results: MEDIUM decides exactly every 24 frames; HARD decides at 32 different intervals within 6..37 frames and covers 78..373 px.
  - It also checks that the three paths differ by 78–95 px on average, that HARD reverses 4× more often than EASY, and that the HARD path depends on the seed.
- **Bugs found and fixed:**
  - HARD waited dwell + 1 frames between decisions.
  - The pursuit gain of 1/16 kept the bird in the middle of the screen; it is now 1/8.
  - The one-bit-per-frame LFSR produced correlated targets; it now leaps 16 steps per frame.
- **`tb_autopilot`** now plays all 9 combinations (3 difficulties × 1–3 columns) for 2,500 frames each. The autopilot never crashes, which shows every mode is playable, and the scores match independently counted passes.
- **Timing:** setup slack fell to +11.9 ns because of the pursuit arithmetic, which is still ample at 31.7 ns per clock.

## M2–M8 integrated build (programmed 2026-09-16)

**Clean full compile:** 89 s wall-clock (Analysis & Synthesis 7 s, Fitter 70 s, Assembler 3 s, TimeQuest 4 s), 0 errors, 0 critical warnings.

**Resources:** 1,125 / 41,910 ALMs (3%), 526 registers, 61,440 / 5,662,720 memory bits (1%), 9 / 553 RAM blocks, 0 / 112 DSP, 1 PLL.

**Timing:** met in all corners. Worst setup slack +11.87 ns, hold +0.170 ns, recovery +27.1 ns, removal +0.46 ns, design-wide TNS 0.

**Warnings: 60, all expected.**

| Warning | Count | Cause |
|---|---|---|
| 15706 (+15705, 171167) | 36 | Pin assignments embedded in the supplied `KBDINTF.qxp` for demo nodes that don't exist here |
| 13049 (+13046) | 17 | `lpm_rom` internal tri-state outputs converted to wires (the supplied demo shows 48) |
| 13410 (+13024) | 2 | `AUD_XCK` and `AUD_DACDAT` intentionally held low |
| 15714 | 1 | Default drive strength (the supplied demo shows the same) |

**Programming:**
- File: `fpga/output_files/controlled_maze.sof`, built 2026-09-16 20:59:36, checksum `0x00EDE942`.
- Command: `quartus_pgm -c "DE-SoC [USB-1]" -m jtag -o "p;output_files/controlled_maze.sof@2"` (the FPGA is JTAG device 2; device 1 is the HPS).

**Simulation:** 13 self-checking testbenches pass: `tb_autopilot`, `tb_bcd`, `tb_bird`, `tb_collision`, `tb_game_fsm`, `tb_keys`, `tb_lfsr`, `tb_maze`, `tb_obstacles`, `tb_score`, `tb_text`, `tb_vga_timing`, `tb_water`. `tb_render +scenario=tour +difficulty=2 +columns=2` renders the screenshots in `docs/screenshots/m8/`.

**Board check:** pending the team's physical test.

## M9 — AI plumbing and WATCH AI with a hand-set network (2026-09-16/17)

The ML design (M9–M12) was approved with the user's decisions D1–D5; see `DESIGN.md` section L.

### D1 — device string, scratch-copy check
- `jtagconfig` shows the FPGA as JTAG device 2 with IDCODE `02D020DD` ("5CSEBA6(.|ES)/5CSEMA6/..").
- A copy of the project in `build/d1_scratch` (not tracked) was compiled with `DEVICE 5CSEMA6F31C6`. Compared with the `5CSXFC6D6F31C6` build:
  - same ALMs, registers, memory, 553 M10K and 112 DSP;
  - same timing (+11.180 ns setup, +0.118 ns hold);
  - every design pin has the same location, I/O standard and bank.
  - The only differences are 18 transceiver no-connect pins that exist only on the SX part, the user-I/O total (457 vs 499) and the PLL total (6 vs 15).
- The main project keeps its `DEVICE` line until the scratch `.sof` (`build/d1_scratch/fpga/output_files/controlled_maze.sof`, HEAD `2a77c15` + new device string) has also been checked on the board.

### What changed
- **M9.1 — seed before restart.** A round now restarts one clock after its seed is loaded. Before, the first openings came from the previous random state. A round is now a pure function of its seed. `tb_golden` hashes every `game_logic` output change (with its clock number) in scripted sessions of all nine modes, and checks that equal seeds give equal rounds after different histories. That seed check fails on the previous `game_logic`.
- **M9.2 — world/lane split.**
  - `world_engine` = `bird_trajectory` + LFSRs + `column_track`.
  - `lane_engine` = `maze_control` + `gap_place` + `collision_detect`.
  - `obstacle_manager` is now a wrapper around `column_track` and `gap_place`.
  - The golden hashes match bit-exactly.
- **M9.3 — network and features.**
  - `ml_pkg`, `feature_world`, `feature_lane`, `nn_sched`, `nn_datapath`.
  - `tools/nn_tool.tcl` converts `assets/nn/demo_net.txt` (a PD controller written as a 4-6-1 network) into `.mif`/`.hex`.
- **M9.4 — text screens, modes, WATCH AI.**
  - **Text-screen engine:** `char_screen`, generated by `tools/screen_tool.tcl` from `assets/screens/screens.txt` into `pages.mif`, `fields.mif`, `words.mif` and `ui_pkg.sv`. It uses 16×16 menu pages, 8×8 overlays, dark panels, and DEC/DECB/SDEC/HEX/WORD/CURSOR fields.
  - **Font:** eleven new glyphs: `# % ( ) + , = [ ] ^ _`. By project convention `#` is a solid block and `^` an up arrow.
  - **`mode_fsm`:** the MODE MENU (HUMAN PLAY / TRAIN AI / WATCH AI), the NO TRAINED AI page, the training setup and a training placeholder page, KEY1 back, and the SW1 debug overlay.
  - **`game_fsm` additions:** `trainMode` (Enter on the obstacle menu records the training world), `autoStart` (for M12, taken on a tick) and `abort`.
  - **`world_speed_control`:** a `load` input.
  - **`game_logic`:**
    - the random seed is latched on any key press;
    - the AI steers only in PLAY, so every round starts centred;
    - new outputs `mazeVy` and `gapBase`.
  - **`ai_player`:** features plus the network, reading a single-port weight RAM named `WTCH` for the In-System Memory Content Editor, loaded with the demo network.
  - **`button_pulse`:** debounces KEY1 (AK4); SW1 is Y27. Both pins come from the supplied `pin.tcl`.
  - **Layers:** game layers are hidden outside the game modes; the bird keeps bobbing behind the menus, and the menu panels are placed so they never cover it.
  - **LEDs:** in WATCH AI, LEDR9 and LEDR8 show UP and DOWN.

### Tests (all pass)

| Testbench | What it shows |
|---|---|
| `tb_golden` | Game unchanged by the split; equal seeds give equal rounds |
| `tb_nn` | All 65,536 products; hard-tanh and truncation edges; 39-clock evaluation; enable/clear; demo network edges; 20,000 random networks match an integer model. Largest sum 73,664 against the 131,071 limit |
| `tb_features` | 50,000 random layouts and 29,700 real-round frames match a reference; off-screen columns are never used |
| `tb_char_screen` | After every load and field pass, all 4,800 cells equal a model built from the same `.mif` files. 6,451,200 rendered pixels equal the model's rendering. Literal format checks. Layer hidden during page changes. Longest field pass 481 clocks, against about 25,800 clocks of blanking before the first visible line |
| `tb_mode_fsm` | Every mode path, the cursors, KEY1, NO TRAINED AI, routing outputs and pages |
| `tb_watch` | Headless WATCH AI in all nine modes at speeds 1, 3 and 6. The maze never moves in GET READY and always follows the action; all 66,432 actions equal the reference model; score equals the columns passed. The demo network survived all 2,500 frames in 26 of 27 runs (EASY, 3 columns, speed 6 crashed after 920 frames) |
| `tb_game_fsm`, `tb_world_speed` | Extended for `trainMode`, `autoStart`, `abort` and `load` |
| Existing tests | Unchanged and passing |

- `tb_render +scenario=tour` now starts at the mode menu and also shows the training setup and placeholder. `tb_render +scenario=watch` records WATCH AI with the SW1 overlay and KEY1.
- `sim/run_tests.sh` now reports a test that ends without a PASS line, and links `altera_mf_ver` (for `ai_player`'s `altsyncram`).

### Tool issues found
- The `lpm_rom` simulation model stops the simulation when the address goes past the last word. `char_screen` therefore addresses its page ROM only while reading it.
- Quartus 17 adds read-during-write pass-through logic to the inferred character RAM (warning 276020). It is harmless here, and Quartus 17 ignored the `no_rw_check` attribute.
- Warning 10027 ("index expression is not wide enough") on `feature_world.sv` line 46 is a front-end quirk: a 2-bit index into a 3-element array. `tb_features` confirms the selection is correct.
- The supplied `melody_player_1` has a register with both preset and clear. Quartus emulates it with latches (warnings 13004/13310/335093, present since the audio commit). It is outside the AI work and is noted here.

### Build (2026-09-17 00:53)
- **Full compile:** 95 s, 0 errors, 0 critical warnings.
- **Resources:** 2,051 ALMs (5%), 1,507 registers, 418,048 memory bits (7%), 66 of 553 RAM blocks (12%), 4 DSP blocks.
- **Where the memory went:**
  - page ROM: 6 pages × 4,800 × 10 bits;
  - character RAM: 4,800 × 10 bits;
  - field, word and font ROMs;
  - the `WTCH` weight RAM.
- **Timing:** met in all corners.
  - Worst setup +11.30 ns, worst hold +0.122 ns.
  - The JTAG hub of the In-System Memory Content Editor adds the `altera_reserved_tck` clock, which also meets timing.
- **Programming file:** `fpga/output_files/controlled_maze.sof`, checksum `0x02282745`.

## M10 — Real parallel evaluation on the training screen (2026-09-17)

Eight real candidate lanes run on the FPGA and the VGA shows exactly those lanes. No evolution yet: M10 evaluates a fixed population (`assets/nn/pop_m10.txt`), with one hand-set controller in each batch next to seven random networks. Design details are in `DESIGN.md` section L.

### What was built
- **Simulator:** `train_lanes` = one shared `world_engine` + 8 × `train_lane` (`lane_engine` + `feature_lane` + `nn_datapath` + fitness counters + the lane's picture), one `feature_world`, one `nn_sched` and a 64-bit-per-gene lane weight memory. A step is 48 clocks and is ordered like a game frame. A run is seed → restart → 88 GET READY steps → PLAY until no lane is alive and not done.
- **Fitness counters:** gates, steps, centred steps and completed runs per lane. Fitness = {gates, steps + centred steps}. Dead lanes freeze.
- **`sim_throttle`:** SIM ×1, ×2, ×4, ×16, ×64, ×256, ×1024, MAX. Numpad 4/6 change it only on the training screen (a second `world_speed_control`, reset ×4).
- **`world_seeds`:** 15-bit maximal LFSR, 15 steps per draw, two new training worlds (bit 15 = 0) per generation. The validation and test seeds (bit 15 = 1) are constants in `ml_pkg`.
- **`train_ctrl` (M10 version):** generation = 8 batches × worlds A_g, B_g; fitness memory; `top8_list`; generation best; mean survival; pauses at SIM ≤ ×16.
- **`train_top`:** throttle, steps-per-second counter, and the atomic per-frame snapshot, granted between steps.
- **`lane_view_draw`:** the eight 1/4-scale lane windows, with the game's coral and bird art, lane-state borders, and dead lanes darkened and crossed out.
- **Training screen:** page TRAIN in `screens.txt`. `char_screen` fields are now 43-bit (15 pages, 256 fields, 256 sources, 128 words), with a new BAR format. The text writer starts 64 clocks after the frame starts, after the snapshot.
- **`mode_fsm`:** TRAIN AI starts the trainer; KEY1 stops it and returns to the mode menu.
- **Indicators:** LEDR[8:1] = lanes alive, LEDR9 = generation beat, HEX5–3 = generation, HEX2–0 = best gates.
- **Tools:** `tools/pop_tool.tcl` builds `pop_init.mif`/`.hex`. `sim/run_tests.sh` accepts `SIMDIR=` for parallel runs.

### Tests (new)

| Testbench | What it shows |
|---|---|
| `tb_lane_equiv` | 8 lanes against 8 separate `game_logic` + `ai_player` games (same networks, seeds, settings) in all 9 modes at world speeds 0, 3 and 7: 174,881 lane-steps with equal maze offset and collision; equal death step, gates = score, steps, centred steps and completed runs (85 deaths, 131 runs completed at the 1,200-step test limit). Lane 0 is identical next to two different sets of networks. Dead lanes stay frozen (maze, action, counters, picture). Idle lanes stay idle. Accumulators add over two runs and clear on `stageClear` |
| `tb_train_sched` | 3 generations at MAX (runs cut at 200 steps): every candidate plays exactly A_g and B_g once, in the lane that shows it, with its own genes. The worlds change every generation. The fitness memory, top-8 list (stable sort), generation best, mean survival and evaluation counter match a reference. 232 snapshots all equal the trainer state at the grant, granted between steps, within 48 clocks; a lane is shown DEAD exactly when it died before the grant. The pause after a run at ×16, abort, and restart with a new RUN ID also work |
| `tb_world_seeds` | 32,767 different training seeds, then the sequence repeats. Bit 15 = 0, never 0. Same RUN ID gives the same sequence, a different RUN ID a different one. A_g ≠ B_g ≠ A_{g−1} for 255 generations. The 12 fixed seeds are distinct with bit 15 = 1. Throttle intervals are exact for all 8 levels (MAX = 49 clocks per step) |
| `tb_train_view` | 3,686,400 pixels of the lane windows equal a reference renderer (all lane states, random pictures, the bird in front of coral, the backdrop); nothing is drawn outside TRAIN AI |
| `tb_train_screen` | Whole system: training started with the keys. For 8 frames at ×4, MAX and ×16, every lane label and the header equal the snapshot the windows are drawn from. One snapshot per frame, always before the text writer. LEDs and HEX follow the trainer. Numpad 4 changes only the simulation speed. KEY1 stops training |
| `tb_char_screen`, `tb_mode_fsm` | Updated for the new field format, the BAR format and the TRAIN page / KEY1 stop |

`tb_render +scenario=train +sim=<level>` records the training screen (`docs/screenshots/m10/`).

### Build (2026-09-17 02:20)
- **Full compile:** 221 s (Analysis & Synthesis 25 s, Fitter 169 s), 0 errors, 0 critical warnings.
- **Warnings:** 252. The new ones are 12010-style port-width notes, all fixed, and nothing else. The M9 set is unchanged: `KBDINTF` pin notes, `lpm_rom` tri-states, the `melody_player_1` latch emulation (13004/335093), the `reset_sync` clock note (332060, also in M9), and 276020 on the character RAM.
- **Resources:** 6,591 ALMs (16%), 6,319 registers, 507,648 memory bits (9%), 78 RAM blocks (14%), 14 DSP blocks (13%).

  | Block | ALMs | Registers |
  |---|---|---|
  | `train_top` (total) | 3,549 | 4,579 |
  | 8 × `train_lane` | ~265 each (about 120 `lane_engine`, 48 `feature_lane`, 47 `nn_datapath`) | ~265 each |
  | `train_ctrl` | 485 | 676 |
  | Snapshot and throttle | 339 | 1,441 |
  | `lane_view_draw` | 285 | 118 |
  | `char_screen` (now 107 fields) | 659 | 351 |

  The plan estimated about 380 ALMs per lane and 6,900 in total; the measured figures are 265 and 6,591.
- **Timing:** met in all corners. Worst setup +10.43 ns (Fmax 46.9 MHz against 31.5 MHz), worst hold +0.113 ns.
- **Programming file:** checksum `0x02E94D6D`. It was not programmed: the next board test is the complete M12 system.

### Measured simulator speed
A step is 48 clocks plus one clock before the next step starts. At MAX that is **642,857 steps/s for all 8 lanes together** (5.1 million lane-steps/s), 8,857× real time (measured in `tb_world_seeds`). A snapshot delays one step by at most one clock per frame.
- With the M10 population, the 16 runs of a generation (runs cut at 200 steps in `tb_train_sched`) take about 307,000 clocks (9.7 ms) including loading.
- A full-length run (88 + 4,095 steps) takes 205,000 clocks = 6.5 ms at MAX.
- The training screen shows the measured steps per second (STEPS/S) on the board.

## M11 — Real genetic learning on the FPGA (2026-09-17)

The trainer now evolves its own population. Design details are in `DESIGN.md` section L (Genetic learning).
- **Start:** a random population is drawn from the RUN ID.
- **Each generation:** two new training worlds (D3). Tournament selection, neuron-block crossover and adaptive mutation, with 2 elites.
- **Validation:** the top 8 play 4 fixed validation worlds. The champion is the best validation score ever seen, kept in `CHMP`.
- **Stop:** after 100 generations, when SOLVED, or on STOP (KEY1). Then the champion plays 8 unseen test worlds, and its genes are copied into the WATCH AI memory (`WTCH`) with its settings and results.
- **WATCH AI** starts the trained champion at once in its training world. It is the exact network the FPGA trained: the replay test below reproduces its scores.
- **Screen:** the training screen shows the validation panel, the champion, the final test and a learning chart.
- **JTAG:** `train_probe` (In-System Sources and Probes "TRNP") and `tools/train_probe.tcl` read and drive training from the PC.

### What was built
- `train_ctrl` (M11): `INIT_POP` → generation loop (train, validate, evolve, commit) → final test → `WATCH_COPY` → `COMPLETE`.
  - Memories: population A/B (their roles swap), fitness memory, `CHMP`.
  - STOP is acted on at the next run, pause or load. A STOP before any champion exists commits nothing. A second STOP skips the final test.
- `xorshift32` (GA random numbers, separate from the world seeds).
- `train_top`: the stop/abort/hold/commit interface, and the committed-AI registers without reset (D2).
- `chart_draw`: learning chart with its 128-entry history memory. `train_probe`, `sim/models/altsource_probe.sv`, `tools/train_probe.tcl`.
- `mode_fsm`:
  - KEY1 on the training screen = stop and keep the champion; KEY1 or Enter leaves once training is COMPLETE; the screen follows the trainer back to the menu if nothing was kept;
  - WATCH AI with a trained AI starts at once in its training world;
  - the JTAG start, stop and leave requests.
- `game_system`: the trainer's WATCH port drives `ai_player`; the trained settings drive `game_fsm.autoStart` and the world speed; the chart layer; HEX2–0 = champion's validation gates; the RUN ID is also latched by a JTAG start.
- Screens: TRAIN page v2 (GENERATION n/100, validation panel, champion, final test, result, chart legend). The WATCH and WATCH debug overlays name the network (TRAINED / DEMO NET, RUN ID, generations, validation and test worlds).

### Tests
| Testbench | What it shows |
|---|---|
| `tb_ga` | 6 generations with every memory shadowed:<br>• INIT_POP: 2,368 genes, each equal to its random word.<br>• Every lane of every training, validation and test run holds the right genes and seed.<br>• The fitness memory is written only by training runs.<br>• Generation top, champion rule, champion genes, stall and mutation level match the reference.<br>• Elites and all 13,764 child genes equal a reference tournament, crossover and mutation (6.1% of genes mutated at level 0; 75% of children crossed over, as designed).<br>• History entries, population swap, final test, WATCH copy, a single commit, and COMPLETE until left. |
| `tb_train_flow` | • A STOP before any champion commits nothing.<br>• A run to MAX_GEN commits the right settings and results.<br>• **Replay:** the committed genes, played through `game_logic` + `ai_player` (the WATCH AI path), reproduce the champion's validation score on V1–V4 and the final test score on T1–T8 exactly.<br>• TRAIN AGAIN stopped early keeps the old AI; stopped later, it replaces it.<br>• KEY0 keeps the AI.<br>• A STOP during the final test skips it and still commits.<br>• SOLVED ends a run (SOLVE_STALL = 1). |
| `tb_train_sched` | Updated: the genes are checked against the shadowed GA population; validation and test runs are excluded from the batch log |
| `tb_mode_fsm` | Stop / complete / leave, the stop without a champion, JTAG start, stop and exit, and the trained WATCH AI's automatic start |
| `tb_char_screen`, `tb_train_screen` | Updated for the TRAIN v2 layout (BAR, SIM, mutation rate, result and test-world words; the chart area stays free of text) |
| `tb_learn` (not in the default list) | Full-length learning in simulation. For RUN 3F2C (MEDIUM, 2 corals, speed 2):<br>• the champion completed 3 of 4 validation worlds at generation 3 and all 4 at generation 8;<br>• mean training survival rose from 4% to 52% by generation 11;<br>• that took 0.97 s of board time. |

### Measured on the board (M11 build, checksum `0x03261FCB`, 2026-09-17 04:35–04:38)
The board was programmed with `quartus_pgm` and every run was started and logged over JTAG (`quartus_stp -t tools/train_probe.tcl run <d> <c> <s> 7 …`) at SIM MAX.
- The M11 build latches the RUN ID only on a key press, so all JTAG runs used RUN ID 7FFF (the `random.sv` reset value). Two MEDIUM runs gave identical results, which shows that training on the hardware is deterministic.
- The log starts a few generations late because the JTAG tool needs time to start.
- The logs are in `build/board_*.log`.

| World trained on | Champion completes V1–V4 at | Stop | Time to COMPLETE (log clock) | Final test (8 unseen worlds) |
|---|---|---|---|---|
| EASY, 1 coral, speed 2 | generation 3 | SOLVED at generation 98 | 12.3 s | 8/8 worlds, 88 gates, 100% |
| MEDIUM, 2 corals, speed 2 | generation 5 | SOLVED at generation 81 | 10.0 s | 8/8 worlds, 176 gates, 100% |
| HARD, 3 corals, speed 3 | generation 5 | SOLVED at generation 70 | 8.7 s | 8/8 worlds, 336 gates, 100% |
| HARD, 3 corals, speed 7 (hardest) | generation 7 | SOLVED at generation 41 | 4.0 s | 4/8 worlds, 440 gates, 72% |

- **Throughput:** the on-screen/probe counter reads **641,180–641,536 steps/s** at MAX. That is 8 lanes × 641,000 = 5.1 million lane-steps per second, against 642,857 in theory. The difference is the per-frame snapshot and the scheduler states.
- **Training speed:**
  - a late generation (most candidates survive all 4,095 steps) takes about 0.13 s;
  - a whole MEDIUM run from start to the committed champion takes about 10.5 s;
  - 81 generations = 5,184 candidate evaluations plus 324 validation runs and the 8-run final test.
- **Validation–test gap:** none for EASY, MEDIUM and HARD at speed 3. At speed 7 the champion completed all 4 validation worlds but only 4 of the 8 unseen worlds. This is the optimism the final test is there to show.

### Build (2026-09-17 04:50, final M11)
- **Full compile:** 230 s, 0 errors, 0 critical warnings, 223 warnings.
- **New warnings (all expected):**
  - 12241 port-connectivity notes for the JTAG pins of `altsource_probe`, which the SLD hub connects after synthesis;
  - the rest is the M9/M10 set.
- **Resources:** 7,165 ALMs (17%), 7,144 registers, 545,280 memory bits (10%), 85 RAM blocks (15%), 16 DSP (14%).
  - `train_top` 3,954 ALMs (`train_ctrl` 909), `chart_draw` 39, `train_probe` 117, `lane_view_draw` 287, `char_screen` 585.
- **Timing:** met in all corners. Setup +9.03 ns (Fmax 46.5 MHz), hold +0.093 ns. The JTAG clock `altera_reserved_tck` also meets timing.
- **Programming file:** checksum `0x0325E5FF`. The measurements above used the first M11 build (`0x03261FCB`). The only difference is that the RUN ID is now also latched by a JTAG start.

### Tool issues found
- ModelSim's precompiled `altera_mf` library has an `altsource_probe` model that leaves the source outputs floating (z), so the simulation-speed mux went X in `tb_train_screen`. `run_tests.sh` now searches `work` first (`-L work`), and `sim/models/altsource_probe.sv` (sources = 0) is used.
- `get_insystem_source_probe_instance_info` must be called before `start_insystem_source_probe`; otherwise quartus_stp reports an already active session.
- Quartus 17 reported an out-of-range index in a `for` loop with a variable bound (`top8_list`, M10). The loop now has constant bounds.

## M12 — Complete product (2026-09-17)

- **No demo network:** only a network trained on the FPGA is a TRAINED AI (`DEMO_NET = 0`).
- **New screens:** the pause menu (RESUME / KEEP THE BEST / DISCARD RUN) and TRAINING COMPLETE (WATCH AI / TRAIN AGAIN / MAIN MENU).
- **Also:** the completion sound, the mode menu names the trained AI, and the final control map, indicators, persistence and debug support.
- Details are in `DESIGN.md` section L (Complete product, Persistence, Control map, Indicators, Debug support).

### What changed
- **`mode_fsm`:** PAUSE and DONE modes.
  - KEY1 / Enter on the training screen open the pause menu, which holds the trainer (`trainHold`). KEEP THE BEST = stop; DISCARD RUN = abort (old AI kept).
  - DONE: WATCH AI starts the champion; TRAIN AGAIN restarts the trainer with its last world (`trainAgain`); MAIN MENU or KEY1 go back.
- **`train_ctrl` / `train_top`:** a start while COMPLETE begins a new run (TRAIN AGAIN), and the settings are latched then too.
- **`game_system`:**
  - `DEMO_NET = 0`, so the `WTCH` memory starts empty;
  - `hold` and `trainAgain` wiring;
  - completion chime (3 × score jingle, SW0 mutes);
  - new text sources (pause and done cursors, test state, AI status, blank-able RUN ID).
- **`char_screen`:** 512 fields; a HEX field with bit 31 set is blank.
- **`chart_draw`:** 2-px champion line.
- **Screens:** pages PAUSE and DONE (the training screen with a box); the MODE page line "TRAINED AI NONE / RUN xxxx"; new header hints.
- **Tools:** `tools/ai_memory.tcl` (dump `WTCH`/`CHMP`, save `WTCH`); `tools/train_probe.tcl` `run` = start + log in one session.
- **`tb_render`:** `+scenario=watch` is now the product flow (NO TRAINED AI → training → pause → TRAINING COMPLETE → WATCH AI → debug overlay → menu). The tour shows the pause menu.

### Tests
| Testbench | What it shows |
|---|---|
| `tb_system` (new) | The whole product (`game_system`) driven only through its inputs (training shortened by parameters to 150-step runs and 2 generations):<br>• after configuration: no AI, the menu says NONE and WATCH AI shows NO TRAINED AI;<br>• TRAIN AI runs to TRAINING COMPLETE with the completion sound;<br>• WATCH AI starts by itself in the training world; `WTCH` holds exactly the champion's genes; the AI steers; SW1 shows the debug overlay naming the trained network;<br>• KEY0 keeps the AI and WATCH AI plays it again;<br>• DISCARD RUN keeps the old AI;<br>• KEEP THE BEST → TRAIN AGAIN (same world, new RUN ID) → MAIN MENU replaces it;<br>• SW0 mutes the completion sound. |
| `tb_chart` (new) | Every chart pixel (champion line, generation top, mean bar, axes, 50 % / 100 % guides) against a reference renderer for 0, 1, 57 and 128 generations and while disabled. |
| `tb_mode_fsm` | Rewritten for M12: pause menu (RESUME / KEEP THE BEST / DISCARD RUN), the trainer held while paused, TRAINING COMPLETE items, the TRAIN AGAIN guard, JTAG start / stop / exit, NO TRAINED AI. |
| `tb_train_flow` | New scenario 8: HOLD freezes the trainer (no step, no RAM write); a start while COMPLETE is TRAIN AGAIN with the last settings. |
| `tb_train_screen`, `tb_char_screen` | The PAUSE and DONE pages (cursor, test result, AI status), the blank HEX format, 512 fields. |
| `tb_render +scenario=watch` | The product flow as VGA images (`docs/screenshots/m12`). |

**Result:** all 30 default testbenches pass. `tb_system` takes about 56 minutes in ModelSim ASE; the image render takes about 38 minutes.
- 29 passed in the full regression run.
- `tb_system` was stopped there and re-run on its own with the shortened GET READY and the final page memories.
- After the DONE page cleanup, `tb_char_screen`, `tb_train_screen`, `tb_system` and `tb_render +scenario=watch` were run again.

### Measured on the board (M12 build, checksum `0x0356914A`, 2026-09-17 05:50–05:54)
- **Right after configuration:** `train_probe.tcl status` reported `committed AI 0`, and `ai_memory.tcl dump` read `WTCH` as all zeros. No network is built in, so WATCH AI shows NO TRAINED AI.
- **Training run over JTAG** (`train_probe.tcl run 1 3 4 7`: MEDIUM, 3 corals, speed 4, SIM MAX), RUN ID F41A. The log is in `build/board_m12.log` and `build/board_m12.csv`.
  - The champion finished all 4 validation worlds (200 gates) from generation 0 on. Mean training survival rose from 4% (generation 1) to 93–99% (generations 41–54).
  - The run stopped as SOLVED at generation 54, **6.8 s** after the start. That covers 3,456 candidate evaluations, 216 validation runs and the 8-run final test.
  - **Final test:** 8/8 unseen worlds, 400 gates, 100% survival.
  - **Throughput** read from the probe during training: **641,423–641,531 steps/s** (8 lanes → 5.13 million lane-steps/s).
- **After completion:** `committed AI 1`, and `ai_memory.tcl dump` shows `WTCH` equal to `CHMP` gene by gene (`build/board_m12_mem.txt`, `build/board_m12_net.txt`). WATCH AI therefore plays the exact champion.
- The screen, keys, sound, KEY0 and SW0/SW1 are for the user's physical test (checklist in the final report).

### Build (2026-09-17 06:21, clean final compile)
- **Clean compile:** `fpga/db` and `fpga/incremental_db` were deleted first. Full compile took 277 s, with 0 errors, 0 critical warnings and 224 warnings.
- **Warnings (all expected, the M11 set):**
  - 12241: JTAG ports of `altsource_probe`.
  - 13046/13049: `lpm_rom` tri-states converted.
  - 10027 on `feature_world.sv:46` and `train_ctrl.sv:434`: "index not wide enough", although both indices address every element (the `S_EVO_ELITE` read is checked gene by gene in `tb_ga`).
  - 332060 on the JTAG clock, and the unused-pin notes.
- **Resources:** 7,225 ALMs (17%), 7,118 registers, 652,288 memory bits (12%), 96 RAM blocks (17%), 16 DSP (14%), 1 PLL.
  - `train_top` 3,992 ALMs (`train_ctrl` 928), `char_screen` 594, `lane_view_draw` 287, `train_probe` 118, `mode_fsm` 42, `chart_draw` 42.
  - Growth over M11: +60 ALMs, and +11 RAM blocks for the two new pages and the 512-entry field table.
- **Timing:** met in all four corners.
  - System clock (31.5 MHz): setup +10.56 ns (Fmax 47.2 MHz, slow 0 °C), hold +0.121 ns (fast 0 °C).
  - JTAG clock: setup +9.03 ns, which is the design-wide worst case.
- **Programming file:** `fpga/output_files/controlled_maze.sof`, checksum `0x03568DDE`.
  - The board measurements above used the previous M12 build (`0x0356914A`). The only difference is the DONE page cleanup: two lane labels that stuck out beside the TRAINING COMPLETE box were removed.

### Measured on the board (final build `0x03568DDE`, 2026-09-17 06:45)
- **Right after configuration:** `committed AI 0`; `WTCH` and `CHMP` are all zeros.
- **Training run over JTAG** (`train_probe.tcl run 1 2 2 7`: MEDIUM, 2 corals, speed 2, SIM MAX), RUN ID 860A. The log is in `build/board_final_medium.log` and `.csv`.
  - The champion finished all 4 validation worlds from generation 0. It kept improving (last at generation 92), so the stall never reached 10 and the run went on to MAX GENERATIONS.
  - **Timing:** generation 100 after **12.8 s**, and COMPLETE with the final test at the same log tick. That is 6,400 candidate evaluations.
    - 0.113 s per generation for generations 1–10, when most candidates die early.
    - 0.131 s per generation for generations 60–100, with 94–95% mean survival.
  - **Final test:** 8/8 unseen worlds, 176 gates, 100%.
  - **Throughput:** every full one-second window read **641,4xx–641,534 steps/s**. The first window only counted part of a second, so it read 361,002.
- **After completion:** `WTCH` equals `CHMP` gene by gene (`build/board_final_mem.txt`).
- The board was then configured again, so it starts with no trained AI for the physical test.

### Tool issues found
- **Slow `tb_system`:** with the real 88-frame GET READY it needed more than an hour in ModelSim ASE. It now shortens GET READY to 12 frames, as `tb_render` does. The watched game only has to start here; `tb_train_flow` and `tb_watch` check that the replayed game matches the training world.
