# Controlled Maze (Underwater Flappy Bird) — Architecture & Roadmap

## Context

Technion EE final lab project (044157, summer 2026), Controlled Maze variant. The bird is autonomous and moves only vertically at a fixed X. The **player controls the vertical position of the coral obstacles**, and all controlled columns move together as one system. The design reuses the supplied lab infrastructure from `qar_files_from_labs/VGA_DEMO_Students.qar` and `KBD09091201.qar`. From M9 on, an AI that is trained on the FPGA itself can play the same game (section L).

**Board device** (checked 2026-09-16 with `jtagconfig` on `DE-SoC [USB-1]`):
- The FPGA is JTAG device 2 with IDCODE `02D020DD`, which Quartus lists as "5CSEBA6(.|ES)/5CSEMA6/..". That IDCODE covers the whole Cyclone V SoC A6/C6 die family (110K LE). The fabric budget is therefore 41,910 ALMs, 553 M10K blocks and 112 DSP blocks, whichever part name is used.
- The project was built as `5CSXFC6D6F31C6`. Quartus 17 offers 5CSEBA6 only in U19/U23 packages, while this board's pins (for example `AK29`) exist only in the F31 package.
- A scratch copy compiled as `5CSEMA6F31C6` (the same die in F31, SE family) gave identical resources, identical timing and an identical assignment for every design pin; only 18 transceiver no-connect pins differ.
- The project's `DEVICE` setting changes only after that scratch build has also been checked on the board (decision D1, M9).

Approved by the team on 2026-09-16. Changes to this design are recorded in the relevant section and in `docs/MILESTONES.md`.

## User decisions (locked)

1. **Coral**: rectangle-based state and collision logic; visuals rendered with reusable bitmap/tile graphics.
2. **Bird**: 32×32, 3 animation frames.
3. **Score**: +1 per obstacle column successfully passed.
4. **Controls**: Arrow Up / Arrow Down + Enter. Verified below that the supplied keyboard chain supports arrows with no changes, so numpad 8/2 is not needed.

## Environment facts

- Quartus Prime **Lite 17.0.0 Build 595** at `C:\intelFPGA_lite\17.0\quartus\bin64\` (matches the Quartus 17 lab files); **ModelSim-Intel ASE** at `C:\intelFPGA_lite\17.0\modelsim_ase\`. Compilation, fitter/timing reports, and FSM testbenches can all be run locally. On-board VGA/audio checks must be done by the user.
- **No Python or Node** on this machine; Git-Bash Perl is available. Asset converters (sprite text → `.mif`) will therefore be written as **Tcl scripts run with `quartus_sh -t`**, so any lab PC that has Quartus can regenerate them. Audio uses the supplied `CreateSound.exe` (the Windows build; no Python needed).
- `.qar` restore will use Quartus itself; confirm the exact flag at M0 with `quartus_sh --help=restore`. (The earlier note naming `--restore_archive` was unverified.)

## Measured facts from supplied material (drive the design)

| Fact | Source | Consequence |
|---|---|---|
| 8-bit color is **RRRGGGBB**: `[7:5]`=R, `[4:2]`=G, `[1:0]`=B *(corrected at M1; the design review said 2-3-3)* | `VGA_Controller.sv` bit order + supplied `pin.tcl` routing; confirmed by the supplied art (`smiely.mif` is mostly `F8`/`FC` yellows, `heart1.mif` mostly `E0`/`C0` reds) | Blue has only 4 levels (`00`,`40`,`BF`,`FF` after MSB replication), so the water gradient uses green/blue mixes plus 4×4 ordered dithering |
| `8'hFF` = transparent | `smileyBitMap.sv`, `square_object.sv` | Never use pure white in sprites; the palette uses `8'hDF` (cool white) instead |
| Frame rate ≈ **72.6 Hz**: the counters run 0..832 and 0..520, so a frame is 833 × 521 clocks at 31.5 MHz *(M1 simulation; the review estimated 72.8 Hz from 832 × 520)* | `VGA_Controller.sv` counters | **Contradiction:** `game_controller.sv` comment says 30 Hz. Speeds are calibrated to ~72.6 fps. The same off-by-one also makes `PixelX`/`PixelY` reach 640/480 |
| Colour field names in the supplied code are unreliable | `VGA_Controller.sv` comments call `[1:0]` red; `back_ground_draw.sv` packs `{blueBits, redBits, greenBits}` | **Contradiction:** neither matches the screen. The pin routing and the supplied MIF art are authoritative (RRRGGGBB) |
| `vga_bg.mif` = 2.46 Mbit ≈ **45% of device M10K** | `back_ground_draw.sv` | No full-screen background ROM; use tiles + procedural layers |
| HEX0–HEX5, SW[9:0], KEY[3:0] | `constraints/pin.tcl` | 6 seven-segment digits available |
| `byterec.sv` emits **9-bit `keyCode` = {E0-extended, scancode}** | KBD lab `byterec.sv`; demo `TOP_KBD.bdf` exposes `keyCode[8..0]`, `make`, `brake` from `KBDINTF` | Arrow keys = `9'h175` / `9'h172`; decode with the supplied `singleKeyDecoder` |
| `keyPad_decoder.enter` is **keypad** Enter (`9'h15A`) only | `keyPad_decoder.sv` table | Main Enter (`9'h05A`) needs its own `singleKeyDecoder`; OR the two together |
| `random.sv` = counter latched on an edge, not an LFSR | `RTL/KEYBOARDX/random.sv` | Use it as the **seed** for a new LFSR |
| One `melody_player_1` = one sound at a time; 16 `songs.mif` slots | `melody_player_1.sv`, sound PDF | Needs a small priority `sound_arbiter` |

## A. Session flow

`KEY[0]` reset → **MENU_DIFF** (↑↓ select EASY/MEDIUM/HARD, Enter) → **MENU_OBST** (↑↓ select 1/2/3, Enter) → **READY** (~1 s "GET READY", RNG seeded) → **PLAY** (the bird moves vertically on its own; holding ↑/↓ moves all active coral columns together; the world scrolls at the SW[2:0] speed; +1 per column passed) → collision → **HIT** (~0.7 s freeze, death sound, flash) → **GAME_OVER** (score, best score, ↑↓ select RESTART / MAIN MENU, Enter; input locked for ~0.5 s on entry) → RESTART → READY with the same settings, or MAIN MENU → MENU_DIFF. No reflash. When returning to a menu, the cursor starts on the previous choice.

## B. Top-level FSM — `game_fsm`

States: `ST_MENU_DIFF`, `ST_MENU_OBST`, `ST_READY`, `ST_PLAY`, `ST_HIT`, `ST_GAME_OVER`. Transitions are evaluated on `startOfFrame`; key inputs are one-clock pulses. Outputs: `game_state`, `difficulty[1:0]`, `obstacle_count[1:0]`, `world_enable`, `round_reset`, `menu_cursor`.

## Controls — verified, no supplied-code changes

| Key | keyCode | Instance | Used as |
|---|---|---|---|
| Arrow Up | `9'h175` | `singleKeyDecoder #(.KEY_VALUE(9'h175))` | `keyRisingEdgePulse` in menus; `keyIsPressed` (held) in play |
| Arrow Down | `9'h172` | `singleKeyDecoder #(.KEY_VALUE(9'h172))` | same |
| Enter (main) | `9'h05A` | `singleKeyDecoder #(.KEY_VALUE(9'h05A))` | confirm pulse |
| Enter (keypad) | `9'h15A` | a fourth `singleKeyDecoder` *(as built; simpler than adding `keyPad_decoder` for one key)* | OR'd into confirm |

These instances tap the supplied `KBDINTF` outputs `keyCode` / `make` / `brake`. PS/2 typematic repeats resend the make code, but `keyIsPressed` simply stays high, so a held arrow gives a clean level and never re-triggers menu movement. In play, if both arrows are held the maze does not move.

## C. Difficulty — only the trajectory generator changes

Every mode outputs `bird_y`, `bird_vy`, `traj_state`, using the `FIXED_POINT_MULTIPLIER = 64` idiom from `smiley_move.sv`.

- **EASY**: `phase += PHASE_STEP`; `bird_y = Y_CENTER + ((AMPL*sin(phase)) >>> N)` using a `SinTable.sv`-style LUT. It is deterministic, smooth, and bounded by construction.
- **MEDIUM**: every 24 frames (~0.33 s), one LFSR bit sets the direction; speed is constant between decisions. Inside the edge margin the choice is biased away from the wall, and `y` is clamped.
- **HARD**: random-interval, random-target, rate-limited pursuit. Each decision latches a random target inside the safe band **and** a random dwell of 6–40 frames. Between decisions the bird accelerates toward the target with `|vy| ≤ VMAX` and `|Δvy| ≤ AMAX`, plus ±1 LSB of per-frame jitter. `y` and `vy` are clamped, so there are no teleports.
- **Invariant:** `MAZE_VSTEP ≥ BIRD_VMAX`, so the player can always catch the bird.
- **RNG**: a new `lfsr_rng` (16-bit Galois LFSR) seeded from the supplied `random.sv`, latched on the player's first menu keypress.

## D. Obstacles — rectangle logic, tile rendering (decision 1)

**State (logic only).**
- One shared `maze_control` register, `maze_y_offset`, is the single command target for human or AI.
- Per column *i* (1–3 active): `col_x[i]`, `gap_base[i]`, `enable[i]`, `passed[i]`.
- `gap_top/bottom[i] = gap_base[i] + maze_y_offset ∓ GAP_H/2`, clamped.
- Respawn at the right edge with a new random `gap_base`. Spacing is `SCREEN_W / N`, and spacing > `CORAL_W` is asserted.

**Collision (geometric AABB, `collision_detect`).** Evaluated once per frame, after positions update:
```
x_overlap[i] = bird_hb_right > col_x[i]  &&  bird_hb_left < col_x[i] + CORAL_W
outside[i]   = bird_hb_top < gap_top[i]  ||  bird_hb_bottom > gap_bottom[i]
collision    = |(enable & x_overlap & outside)
```
- The bird hitbox is a parameterized inset of the 32×32 sprite: x 9..25 and y 10..24 (17×15, the body only), so fins, tail and beak are forgiving. The coral collision core is 4 px narrower than the art on each side, and the 8 rows of branch tips next to the opening never collide.
- This costs about 18 comparators per frame and is independent of the artwork.
- **Key payoff:** a headless training simulator has no raster scan, so per-pixel collision could not be reused there. Geometric collision can be reused as-is.
- The supplied `game_controller.sv` once-per-frame flag/`SingleHitPulse` pattern still turns the level into one pulse.
- The supplied per-pixel DR collision (`bird_DR && coral_DR`) is kept only as a SignalTap debug cross-check (`pixel_collision_dbg`) to prove that the art matches the hitboxes.

**Score.** When `col_x[i] + CORAL_W < bird_hb_left` and `!passed[i]`, add +1 and set `passed[i]`. The flag is cleared on respawn.

**Rendering (`coral_draw`, separate from state).**
- `CORAL_W = 64`, using **64×32 tiles**, the same dimensions as the supplied smiley bitmap.
- Tiles: a body tile repeated vertically, plus a **tip tile** at each gap edge. The upper column's tip is the vertically flipped tip (`31 − offsetY`, which needs no extra ROM).
- Tile rows are indexed **relative to the gap edges**, not to the screen, so the coral texture moves with the maze when the player steers.
- **Art rule:** body and tip tiles are opaque across the full width, and the tip is opaque up to the gap edge, so what you see is what you collide with.
- Columns never overlap in X, so one shared tile ROM plus an address mux serves all three columns.

## E. Speed — SW[2:0]

`world_step = 64 + (sw_sync << 5)` in 1/64-px units, giving 1.0, 1.5 … 4.5 px/frame (≈73–327 px/s).
- SW[2:0] passes through a 2-FF synchronizer and is read every frame, so changes apply live.
- The time/score ramp is a separate saturating addend.
- There is a single clock domain (31.5 MHz) with no derived or gated clocks.
- Other switches: SW[3] mute, SW[4] invincibility, SW[5] turbo (feeds `Mili_sec_counter.turbo`), SW[9] pause.

## F. Score

- Score and best score are each stored as 3-digit **BCD** (pattern from `bcddn.sv`) and feed both `SEG7` and the VGA digit renderer directly.
- Best score is compared as a 12-bit vector and updated in GAME_OVER. It survives RESTART and MAIN MENU and resets only on KEY[0] or power cycle.
- 7-seg: **HEX2..0 = current, HEX5..3 = best**, using 6× `SEG7` with `darkN` for leading-zero blanking and a game-over flash.
- On VGA, one shared glyph ROM plus a digit-select mux renders the score.

## G. Graphics

**Layers, back to front:**
1. Procedural depth gradient.
2. Far parallax silhouettes (32×32 tiles, ¼ speed).
3. Near seaweed tiles (½ speed, 2-frame sway).
4. About 12 procedural bubbles.
5. Coral (64×32 body and tip tiles).
6. Bird.
7. HUD.

**Bird (decision 2).**
- 32×32 with 3 frames, played ping-pong (0-1-2-1) with one step every 8 frames (≈9 Hz).
- ROM address is pure concatenation, `{frame[1:0], offsetY[4:0], offsetX[4:0]}`, so no arithmetic is needed. The ROM is 3072×8 = 24.6 Kb.
- The design is original: a side-view fish-bird with a dark navy outline, an amber body (complementary to the water), and a clear cyan fin. It uses ≤8 colors from a shared project palette package, and `8'hDF` (cool white) stands in for white because `8'hFF` is transparent.
- The frames differ only in the fin, so the silhouette stays stable.

**Asset workflow.**
- Sprites and tiles are authored as **ASCII pixel grids plus a palette file**. These are diffable in Git and reviewable.
- A Tcl converter produces `.mif` files.
- An HTML preview of each sprite is shown to the user for approval before conversion.

**Text** *(as built in M5 and M6)*:
- An original 8×8 1-bit font (45 glyphs, ASCII 0x20..0x5F, 4,096 bits), drawn at ×2, ×4 or ×8, so every division is a shift.
- Every text line on every screen is one entry in `text_pkg`.
- The selection highlight is a bar drawn by `ui_panels`, which also draws the translucent checkerboard backdrops and the crash flash.

**Memory.** Planned: bird 24.6 Kb + coral 32.8 Kb + background tiles ~66 Kb + font ~5 Kb ≈ 130 Kb. As of M8: bird 24,576 + coral 32,768 + font 4,096 = **61,440 bits (1%)**. The background is still fully procedural.

## H. Audio

- Reuse `melody_player_1`, `ToneDecoder`, `SinTable`, `Mili_sec_counter`, the codec QXP, and `songs.mif` (built with `CreateSound.exe`).
- Slots: menu move, confirm, score, collision, game-over jingle, new-best fanfare, and an optional theme.
- New `sound_arbiter` priority: collision > new best > game over > score > menu.

## I–J. Reuse and new modules

- **Reused unchanged:** `VGA_Controller`, `square_object`, `SEG7`, `NumbersBitMap`, `singleKeyDecoder`, `keyPad_decoder`, `KBDINTF` (+ `byterec`/`bitrec`/`lpf`), `random`, `melody_player_1`, `ToneDecoder`, `SinTable`, `Mili_sec_counter`, `prescaler`, `addr_counter`, codec QXP, CLK_31P5 PLL, `pin.tcl`, `.sdc`.
- **Extended:** `objects_mux` (split hierarchically), `game_controller` (stubs filled; once-per-frame pulse).
- **Adapted patterns:** `smileyBitMap` → `birdBitMap`; `HartsMatrixBitMap` → background tile layers; `NumbersBitMap` → `glyph_rom`/`text_draw`; `bcddn` → `score_bcd`; `smiley_move` fixed-point idiom → `bird_trajectory`.
- **New modules:**

| Area | Modules |
|---|---|
| Game control | `game_fsm`, `menu_controller`, `key_input` (the three `singleKeyDecoder` instances plus the Enter OR) |
| Bird logic | `bird_trajectory`, `lfsr_rng` |
| Maze and obstacles | `maze_control`, `control_mux` (AI port tied off), `obstacle_manager` (per-column rectangle state, respawn, pass/score pulses), `collision_detect` |
| Score, speed, sound | `score_bcd`, `world_speed`, `sound_arbiter` |
| Rendering | `birdBitMap`, `bird_draw`, `coral_draw`, `water_background`, `bubble_field`, `glyph_rom`, `text_draw`, `digit_field_draw`, `objects_mux_top`, `hex_display_top` |
| ML and shared definitions | `ml_feature_extract`, `game_state_pkg`, `palette_pkg` |

## K. ML-ready interfaces

Superseded in M9 by section L: `game_logic` exports every signal the AI needs (bird Y/speed, column X, opening bases and edges, maze offset and speed, world speed), and the AI steers through `control_mux` only while the game is in PLAY.

## Implementation notes (M2–M8)

- **Module structure:** `controlled_maze_top` (PLL, reset, `KBDINTF` wrapper, codec tie-offs) → `game_system` (VGA timing, key decoding, drawing layers) → `game_logic`. `game_logic` holds every game rule and has no pixel inputs, so testbenches (and later an on-chip trainer) can step it thousands of times faster than real time.
- **Frame order:** each frame's update is split into `tickMove` → `tickCheck` → `tickState`, one clock apart, during vertical blanking.
- **Drawing layers** all have a 3-clock latency and are merged, front to back, as text → panels → bird → coral → water and sand.
- **Asset sources:** `assets/sprites/*.txt` and `assets/fonts/font8x8.txt` are the sources, converted by `tools/sprite_tool.tcl` and `tools/font_tool.tcl` (`quartus_sh -t`). `tools/ppm2png.pl` turns simulated VGA frames into PNGs.
- **Randomness:** the supplied `random.sv` latches a counter on each key press (on each Enter press before M9). That value seeds two 16-bit leap-forward LFSRs (16 steps per frame), one for the coral and one for the bird.
- **Tuned bird motion:**
  - MEDIUM: a decision every 24 frames, 2.5 px/frame, 16/64 px per frame² acceleration.
  - HARD: pursuit gain 1/8, 6..37-frame dwell, 3.75 px/frame, 32/64 px per frame² acceleration, ±4/64 px jitter.
- **Timing setting:** `OPTIMIZE_HOLD_TIMING` is `ALL PATHS`, because the supplied `OFF` setting left a −51 ps hold violation on the pipeline registers.
- **Not yet built** (later milestones): `world_speed` (SW[2:0], M9), audio and `sound_arbiter` (M10), parallax, bubbles and seaweed (M11), `menu_controller` (folded into `game_fsm`), `glyph_rom`/`digit_field_draw` (folded into `text_draw`), `game_controller`-style per-pixel debug collision (optional).

## L. On-fabric training and the AI player (approved 2026-09-16; full proposal in the session plan)

**Goal.** The AI is trained on the FPGA itself. Eight candidates are evaluated in parallel, and the VGA shows those exact simulations. The best network then plays the normal game. Modes: **HUMAN PLAY / TRAIN AI / WATCH AI**.

**Decisions (user, 2026-09-16)**
- **D1:** try the `DEVICE` change only in a scratch copy first (see Context).
- **D2:** KEY0 resets the game and any training run, but keeps an AI that training already committed.
- **D3:** training worlds change every generation. All candidates of one generation play the same two worlds. The champion is chosen on 4 fixed validation worlds, and the final champion is reported once on 8 unseen test worlds.
- **D4:** the speed ramp, animated background, parallax and final polish move to M13–M14.
- **D5:** KEY1 = back / pause, SW1 = AI debug overlay. During TRAIN AI, Numpad 4/6 change only the simulation speed.

**Game split (M9).**
- `world_engine` holds everything the player cannot influence: `bird_trajectory`, both LFSRs, and `column_track` (column motion, openings, passes).
- `lane_engine` holds the player's part: `maze_control`, `gap_place` (the offset clamp) and `collision_detect`.
- `game_logic` uses one of each. The trainer will use one `world_engine` shared by all lanes, which is exact because the world ignores the player, and one `lane_engine` per lane. Training and the visible game therefore use the same rule modules.
- `tb_golden` proves the split changed nothing. It compares per-change hashes of every output, recorded before the split.
- A round restarts one clock after its seed is loaded, so it is a pure function of the seed. Before this change, the first openings came from the previous LFSR state.

**Network (M9).**
- **Inputs:** `feature_world` computes the shared inputs once per step; `feature_lane` computes the per-player ones. The four inputs (int8, Q1.6), all computed from on-screen columns only:
  1. next opening error;
  2. the following opening's error;
  3. relative vertical speed (maze − bird);
  4. frames until the next column arrives (speed-independent).
- **Layers:** a 4→6 hard-tanh layer, then one output with a ±0.25 dead zone that gives UP/HOLD/DOWN.
- **Genes:** 37 signed 8-bit genes (weights Q2.5). Hidden neuron j uses genes 5j..5j+4 as [bias, w0..w3]; the output uses genes 30..36.
- **Arithmetic:** 18-bit accumulator; it provably cannot overflow.
- **Evaluation:** `nn_sched` + `nn_datapath` evaluate the network serially in 39 clocks. Several datapaths can share one scheduler and one memory read.
- **Actions:** they drive the same `maze_control` inputs as Numpad 8/2, and only in PLAY. The 1→4 px/frame ramp therefore applies to the AI exactly as to a human.

**WATCH AI (M9).**
- `ai_player` evaluates the network once per frame, right after the game update, from its weight memory. That memory is a single-port M10K, In-System Memory Content Editor name `WTCH`.
- M9 ships a hand-set PD controller (`assets/nn/demo_net.txt`), so WATCH goes through the normal menus. From M12 it will use the trained champion with the trained settings.

**Text screens (M9).**
- `char_screen` draws the menus, overlays and (from M10) the training screen from `assets/screens/screens.txt`, converted by `tools/screen_tool.tcl`.
- Each page is an 80×60 grid of 8×8 cells, or 40×30 of 16×16. Cells are {panel, colour, glyph}, and there are dynamic fields (DEC, DECB, SDEC, HEX, WORD, CURSOR).
- Once per frame, during vertical blanking, a writer formats the values into a character RAM, so every visible frame shows one consistent set of values.
- This replaces growing `text_pkg` (Quartus 17 crashes at 23 lines).

**Text screens (M10 extension).** Fields are 43-bit words {page 4, row 6, col 7, len 4, fmt 3, source 8, arg 7, attr 4}: up to 15 pages, 256 fields, 256 sources and 128 words. A new BAR format draws a progress bar. `game_system` starts the text writer 64 clocks after the frame starts, after the trainer's snapshot (below).

**Training engine (M10: parallel evaluation).**
- **`train_lanes`** is the simulator: one `world_engine` shared by 8 `train_lane`s. A `train_lane` is one `lane_engine` (maze, openings, collision), one `feature_lane` and one `nn_datapath` (1 DSP), plus the fitness counters and the lane's picture.
  - All lanes share one `feature_world`, one `nn_sched` and one 64-bit weight memory word per gene (8 bits per lane).
  - The world does not depend on the player, so sharing it is exact: every lane of a run plays the same world.
- **Run:** load the seed, then restart one clock later; 88 frozen GET READY steps; then PLAY steps until no enabled lane is alive and not done. This is the order `game_logic` follows in WATCH AI.
- **Step:** 48 clocks, ordered like a game frame:
  - ph 0 move, ph 1 collisions and passes, ph 2 alive/gates/steps and picture;
  - ph 3–4 features, ph 5 network start and centred-step count, ph 44 new actions.
- **Fitness counters per lane** (per PLAY step begun alive):
  - T and accTA + 1; G + 1 on a pass (a pass on the death step counts, as in the game);
  - a collision kills the lane; T = 4095 marks it DONE (W + 1);
  - accTA + 1 more if the step ended alive with the next column on screen and |e_next| ≤ 16 px;
  - fitness = {G[9:0], TA[15:0]}.
- **Dead lanes** freeze: the maze does not move, the network does not evaluate, and the counters and picture keep the death step's values.
- **Throttle (`sim_throttle`):** a free-running divider allows one step every 433,993 / 216,997 / 108,498 / 27,125 / 6,781 / 1,695 / 424 clocks (×1, ×2, ×4, ×16, ×64, ×256, ×1024), or back to back (MAX).
  - During TRAIN AI, Numpad 4/6 drive a second `world_speed_control` (the same stepping rules, reset level 2 = ×4).
  - `game_logic` does not receive those keys then, so the world speed to train on cannot change.
- **Scheduler (`train_ctrl`, M10 version):** a generation plays all 64 candidates of a fixed population (`assets/nn/pop_m10.txt` → `pop_init.mif`: 8 hand-set controllers, one per batch, plus 56 random networks) in 8 batches, each on world A_g and world B_g.
  - A_g and B_g come from `world_seeds`: a 15-bit maximal LFSR seeded from the RUN ID. A draw advances it 15 steps, giving a new seed with bit 15 = 0 every generation.
  - Results go to the fitness memory and to `top8_list` (a stable insertion sort), plus the generation best and the mean survival.
  - At SIM ×1–×16 the scheduler pauses 0.5 s after each run and 1 s after each generation.
- **Snapshot (`train_top`):** `startOfFrame` requests it; the simulator grants it between two steps (at most 48 clocks later) and never while a run is being set up. Every displayed value (lane state, candidate, action, gates, fitness, steps, picture, header, statistics) is copied on that one clock.
- **Training screen:**
  - `lane_view_draw` draws window k from lane k's snapshot at 1/4 scale with the game's own `coral.mif`/`bird.mif` and water colours.
  - Borders: cyan = alive, red = dead (darkened, red cross), green = done, grey = idle.
  - `char_screen` page TRAIN adds the header, the two label lines under each window, the generation statistics and a legend.
- **Indicators in TRAIN AI:** LEDR[8:1] = lanes 7..0 alive, LEDR9 toggles once per generation, HEX5–3 = generation, HEX2–0 = best gates of the generation.
**Genetic learning (M11).** `train_ctrl` is now the full algorithm (the M10 fixed population is gone). A training run is a deterministic function of its RUN ID and settings.
- **Start:** `world_seeds` and the GA generator `xorshift32` (13/17/5) are loaded from the RUN ID. 64 × 37 random genes (−64..63) go into the current population.
- **Generation g:**
  1. **Train.** New worlds A_g, B_g. 8 batches play them; results go to the fitness memory and the top-8 list.
  2. **Validate.** The generation's top 8 (by training fitness) play the fixed worlds V1–V4, all 8 at once. The best lane is the generation top. If its score is strictly better than the champion's, it becomes the champion: its genes are copied into `CHMP` (single-port, In-System Memory Content Editor) and the stall count resets. Otherwise the stall count grows. Validation results never reach the fitness memory.
  3. **Evolve** (into the other population memory; the two swap at COMMIT):
     - slots 0 and 1 = the two best by training fitness;
     - each of the other 62 children: two tournaments of 4 random candidates (first best wins), then with probability 3/4 a uniform crossover of the 7 neuron blocks;
     - then per-gene mutation with probability 1/16, 1/8 or 1/4 (stall < 8, 8–15, ≥ 16). 7/8 of mutations add (a − b) · 2^level (a, b uniform 0..15, saturated); 1/8 draw a fresh gene.
  4. **Commit.** The populations swap. A chart entry {champion %, generation top %, mean %} is written. Then the stop test.
- **Stop:** after 100 generations, when SOLVED (the champion completed V1–V4 and 10 generations passed without a better one), or on STOP.
  - STOP is KEY1, or the JTAG probe. It is acted on at the next run, pause or load.
  - A STOP before any champion exists returns to idle and commits nothing.
- **Final test:** the champion alone (lane 0; lanes 1–7 idle) plays the unseen worlds T1–T8 once. A second STOP skips it.
- **Commit to WATCH AI:** the champion's genes are copied into `WTCH` (the `ai_player` memory). The settings, RUN ID, generation count and validation/test results go into `train_top` registers that have no reset, so KEY0 keeps them (D2). The trainer then stays COMPLETE until the user leaves the screen.
- **WATCH AI with a trained AI:** `mode_fsm` starts the game at once with the trained difficulty, columns and world speed (`game_fsm.autoStart`, `world_speed_control.load`). The game menus and keys are hidden until GET READY.
  - The overlay names the network (TRAINED / DEMO NET), its RUN ID, generations, validation worlds and test worlds.
  - In M11 the demo network is still built in for WATCH AI before anything is trained; M12 removes it.
- **Training screen v2:**
  - Header: GENERATION n/100, stage (TRAINING / VALIDATE / TESTING / EVOLVING / COMPLETE), run state, world (A, B, V1–V4, T1–T8) and seed.
  - Left panel: this generation's best and last best on these worlds; the validation panel (generation top, champion, its generation, stall, mutation rate); the final test; the stop result.
  - Right panel: the learning chart (`chart_draw`), one 2-px column per generation from a 128-entry history memory. Dim bar = mean training survival (its own worlds); cyan = generation top on validation; gold = champion on validation.
- **Indicators:** HEX2–0 now show the champion's validation gates.
- **JTAG (`train_probe`, In-System Sources and Probes "TRNP"):** a 192-bit probe of the snapshot statistics and 16 source bits (start with given settings, stop, leave, simulation-speed override). `tools/train_probe.tcl` (quartus_stp) reads, drives and logs training on the board. `sim/models/altsource_probe.sv` is its simulation stand-in (sources stay 0).
**Complete product (M12).**
- **No demo network:** `DEMO_NET = 0`. The WATCH memory starts empty (`init_file = UNUSED`), and only a network trained on the FPGA counts as a TRAINED AI.
  - After configuration, the mode menu shows TRAINED AI NONE and WATCH AI shows NO TRAINED AI.
  - After training, the mode menu shows TRAINED AI RUN xxxx. A HEX field with bit 31 set is drawn blank.
- **Pause menu** (`mode_fsm` PAUSE, page PAUSE = the training screen with a box). KEY1 or Enter opens it, and the trainer holds between steps (run state PAUSED).
  - **RESUME** (or KEY1) continues.
  - **KEEP THE BEST** stops: final test, then commit.
  - **DISCARD RUN** returns to the menu and keeps the previous AI.
- **TRAINING COMPLETE** (page DONE): result (MAX GEN / SOLVED / STOPPED), RUN ID, generations, world, the champion's generation and candidate, validation and final-test worlds / gates / survival (SKIPPED if a second STOP skipped the test), and a note that the champion is now the WATCH AI.
  - **WATCH AI** plays it at once in its training world.
  - **TRAIN AGAIN** starts a new run in the same world with a new RUN ID. The trainer accepts a start while COMPLETE.
  - **MAIN MENU** (or KEY1) returns to the mode menu.
- **Completion sound:** the score jingle plays three times when training completes. Training itself is silent; SW0 mutes everything.
- **Chart:** the champion line is 2 px thick.
- **Text screens:** up to 512 fields (the TRAIN, PAUSE and DONE pages share the layout); the longest per-frame text pass is 4,478 clocks.

**Persistence (D2).**

| Event | Trained AI (WATCH memory + committed registers) |
|---|---|
| GAME OVER, RESTART, MAIN MENU, KEY1, a new human game | kept |
| TRAIN AI stopped before a champion exists, or DISCARD RUN | kept (the old one) |
| A training run that completes (MAX GEN, SOLVED, KEEP THE BEST) | replaced by the new champion |
| KEY0 | kept: the registers have no reset and M10K contents are never cleared; the trainer itself goes back to idle |
| Reconfiguring the FPGA / power off | lost (the network can be saved first with `tools/ai_memory.tcl save`) |

**Control map (final).**

| Input | Mode menu / NO TRAINED AI | HUMAN PLAY | WATCH AI | TRAIN AI setup | Training screen | Pause menu | TRAINING COMPLETE |
|---|---|---|---|---|---|---|---|
| Numpad 8 / 2 (Arrow Up / Down) | move the cursor | maze up / down; menu cursor | – (the AI steers); menu cursor on GAME OVER | menu cursor | – | cursor | cursor |
| Numpad 4 / 6 | – | world speed faster / slower | world speed faster / slower | world speed to train on | **simulation speed** faster / slower (×1 … MAX) | simulation speed | simulation speed |
| Enter | select | menus, RESTART / MAIN MENU | RESTART / MAIN MENU on GAME OVER | select | open the pause menu | select | select |
| KEY1 | back (NO AI → menu) | back to the mode menu | back to the mode menu | back to the mode menu | open the pause menu | RESUME | MAIN MENU |
| KEY0 | reset (keeps a trained AI) | reset | reset | reset | reset (training is lost, the committed AI stays) | reset | reset |
| SW0 | mute all sound | | | | | | |
| SW1 | – | – | AI debug overlay (inputs F0–F3, h0, output y, network) | – | – | – | – |

**Indicators (final).**
- LEDR0 = PLL locked.
- Game modes: LEDR[4:2] = game screen, [6:5] = difficulty, [8:7] = columns, LEDR9 = heartbeat. In WATCH AI, LEDR9 / LEDR8 = maze up / down.
- Training screens: LEDR[8:1] = lanes 7..0 alive, LEDR9 toggles once per generation.
- HEX: game modes show the best score (HEX5–3) and the score (HEX2–0). Training screens show the generation (HEX5–3) and the champion's validation gates (HEX2–0).

**Debug support.**
- **In-System Sources and Probes `TRNP`** (`train_probe`) with `tools/train_probe.tcl`: live statistics (generation, champion, validation, mean survival, stall, stage, steps/s, final test, RUN ID, evaluations, committed AI); start / stop / leave training and override the simulation speed from the PC; log a whole run to CSV.
- **In-System Memory Content Editor:** `WTCH` (the WATCH AI network) and `CHMP` (the current run's champion). `tools/ai_memory.tcl` dumps them or saves `WTCH` in the `nn_tool` format.
- **SignalTap:** no `.stp` is built into the product (compile time, and a hand-written `.stp` could not be checked). The useful nodes to add with the Node Finder are:
  - `train_top:trainer|train_ctrl:ctrl|state`, `runKind`, `gen`, `batch`, `runIdx`, `g`, `k`, `child`, `tsel`, `rnd`, `popWe`, `popWa`, `popWd`, `fitWe`, `chmpWe`, `stopReq`;
  - `train_lanes:lanes|busy`, `ph`, `running`, `playing`, `playSteps`, `alive`, `done`, `enabled`, `snapReq`, `snapGrant`;
  - `lane[0].unit|network|acc`, `act`;
  - `mode_fsm:modes|mode`, `cursor`.

## M. Risks

- The full-screen background ROM is avoided.
- Duplicate ROMs are prevented by sharing each ROM behind an address mux.
- All sizes are kept at 2ⁿ to avoid real multipliers.
- No large unrolled `for` loops; the object MUX is split hierarchically.
- Signed/`int` mixing is a bug risk.
- **Pipeline latency alignment:** every layer must reach the MUX with the same latency, or objects will shift by a pixel. Registered-address ROMs add one clock.
- **Art/hitbox mismatch:** caught by the `pixel_collision_dbg` cross-check.
- **Lost PS/2 break byte:** a parity drop in `bitrec` could leave an arrow "held" until it is pressed again. This is low probability, recoverable, and noted.
- **Audio codec state survives FPGA reprogramming:** any build without the audio block must drive `AUD_XCK` and `AUD_DACDAT` low, otherwise a previously configured codec produces noise (found at M1).
- Keep the supplied `FAST_FIT` and `INCREMENTAL_COMPILATION` settings.

## N. Roadmap

Each milestone compiles, runs, is committed to Git, and is archived as `.qar`. Testbenches run in ModelSim where noted.

| # | Milestone | Verification |
|---|---|---|
| M0 | `.gitignore` for Quartus noise; restore the supplied qar; compile unmodified; record baseline compile time and resources | Compile report; user sees the demo on the board |
| M1 | Project skeleton, palette package, water gradient, static bird rectangle | VGA check |
| M2 | EASY `bird_trajectory` + bird sprite (ASCII art → HTML preview → MIF) | TB: trajectory bounds; VGA |
| M3 | One scrolling coral column (rectangle state + tile render) + AABB collision freeze | TB: `collision_detect` cases; VGA — *initial-implementation checkpoint* |
| M4 | `key_input` arrows/Enter + `maze_control` + `control_mux` | **Playable MVP / "FULL PIPE"** |
| M5 | `score_bcd`, 6× 7-seg, on-screen digits, best score | TB: BCD carry, best-score update |
| M6 | Glyph ROM, `text_draw`, both menus, full `game_fsm`, RESTART/MAIN MENU | TB: `game_fsm` (report module #1) |
| M7 | 2 and 3 columns via `obstacle_manager` | Multi-column collision and score TB |
| M8 | MEDIUM + HARD + `lfsr_rng` | TB: `bird_trajectory` bounds over long random runs (report module #2) |
| — | *(as built after M8: Numpad 4/6 world speed, score and failure sounds; SW0 mute)* | Board check |
| M9 | World/lane split, seed-then-restart, fixed-point network and features, text-screen engine, mode menu, WATCH AI with a hand-set network, KEY1/SW1 | `tb_golden`, `tb_nn`, `tb_features`, `tb_char_screen`, `tb_mode_fsm`, `tb_watch`; board |
| M10 | 8 parallel evaluation lanes, step throttle, fitness, batch scheduler with a fixed population, training screen v1 | Lane-equivalence and independence TBs; 8 real candidates on VGA |
| M11 | Genetic algorithm, per-generation worlds, validation and champion, final test, learning chart | GA unit TBs, mini-generation TB; learning curves measured on the board |
| M11b | GA tuning (only if M11 measurements require it) | Measured |
| M12 | TRAIN → COMPLETE → WATCH flow, pause/stop, persistence, debug/HEX/LED, docs | Train-flow TB (replay reproduces scores); full demo |
| M13 | Dynamic difficulty: speed ramp and obstacle rate (spec 90 tier); training inherits it through `world_engine` | TBs; board |
| M14 | Animated background, parallax, final art and polish, final report | Board |
