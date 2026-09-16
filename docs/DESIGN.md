# Controlled Maze (Underwater Flappy Bird) — Architecture & Roadmap

## Context

Technion EE final lab project (044157, summer 2026), Controlled Maze variant. The bird is autonomous and moves only vertically at a fixed X. The **player controls the vertical position of the coral obstacles**, and all controlled columns move together as one system. The target board is a Cyclone V `5CSXFC6D6F31C6` (DE10-Standard class), reusing the supplied lab infrastructure from `qar_files_from_labs/VGA_DEMO_Students.qar` and `KBD09091201.qar`. ML is deliberately deferred until the base game is complete, but the architecture must not block on-chip training later.

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

## K. ML-ready interfaces (defined now, unused)

- `game_state_pkg` exposes `bird_y`, `bird_vy`, `traj_state`, `next_obst_dx`, `next_obst_gap_y`, `dy_error`, `maze_y_offset`, `world_step`, `difficulty`, `obstacle_count`, `score_bcd`, `collision`, `game_state`, and `frame_tick`.
- `control_mux` already has the `ai_up`, `ai_down`, `ai_valid`, and `ai_mode` ports.
- `ml_feature_extract` has been postponed to M13. `game_logic` already outputs every signal it needs (bird Y/Vy/state, maze offset, column X, opening edges, collision, score).

## Implementation notes (M2–M8)

- **Module structure:** `controlled_maze_top` (PLL, reset, `KBDINTF` wrapper, codec tie-offs) → `game_system` (VGA timing, key decoding, drawing layers) → `game_logic`. `game_logic` holds every game rule and has no pixel inputs, so testbenches (and later an on-chip trainer) can step it thousands of times faster than real time.
- **Frame order:** each frame's update is split into `tickMove` → `tickCheck` → `tickState`, one clock apart, during vertical blanking.
- **Drawing layers** all have a 3-clock latency and are merged, front to back, as text → panels → bird → coral → water and sand.
- **Asset sources:** `assets/sprites/*.txt` and `assets/fonts/font8x8.txt` are the sources, converted by `tools/sprite_tool.tcl` and `tools/font_tool.tcl` (`quartus_sh -t`). `tools/ppm2png.pl` turns simulated VGA frames into PNGs.
- **Randomness:** the supplied `random.sv` latches a counter on each Enter press. That value seeds two 16-bit leap-forward LFSRs (16 steps per frame), one for the coral and one for the bird.
- **Tuned bird motion:**
  - MEDIUM: a decision every 24 frames, 2.5 px/frame, 16/64 px per frame² acceleration.
  - HARD: pursuit gain 1/8, 6..37-frame dwell, 3.75 px/frame, 32/64 px per frame² acceleration, ±4/64 px jitter.
- **Timing setting:** `OPTIMIZE_HOLD_TIMING` is `ALL PATHS`, because the supplied `OFF` setting left a −51 ps hold violation on the pipeline registers.
- **Not yet built** (later milestones): `world_speed` (SW[2:0], M9), audio and `sound_arbiter` (M10), parallax, bubbles and seaweed (M11), `menu_controller` (folded into `game_fsm`), `glyph_rom`/`digit_field_draw` (folded into `text_draw`), `game_controller`-style per-pixel debug collision (optional).

## L. On-fabric training — preliminary (unchanged, now strengthened)

- **Size:** 4→4→1 = 25 weights; a population of 32 at 16 bits is 12.8 Kb (one M10K). Inference is 20 MACs on one DSP.
- **Throughput:** about 117 ms per generation in the worst case, so 100 generations take ≈12 s (~8,000× real time). The estimated cost is 1–4 DSP, 1–2 M10K, and ~1–3K ALM.
- **Neuroevolution rather than backprop:** there is no labeled data, fixed-point gradients underflow, and neuroevolution reuses the inference datapath.
- **Why decision 1 helps:** geometric collision is what makes it possible to re-instantiate the *same* game-logic modules inside a fast headless simulator.
- **Measurements needed before committing:** base-game ALM/M10K/DSP headroom, base-game compile time, measured frame rate, and the number of generations needed.

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
| M9 | SW[2:0] speed + ramp + cheat/turbo/mute/pause | Live switch check |
| M10 | Audio: `songs.mif` + `sound_arbiter` | Listen on board |
| M11 | Final art, parallax, bubbles, shimmer; re-measure resources | Compile under 10 min |
| M12 | SignalTap captures, docs, resource report | **Base game complete** |
| M13–M14 | `ml_feature_extract` + fixed-point inference; AI mode with hand-set weights | AI plays via `control_mux` |
| M15–M17 | Headless simulator reusing game modules; on-fabric GA; on-chip training demo | Fitness rises; best net drives live play |
