// Tunable game constants shared by logic and drawing modules.

package game_params_pkg;

  localparam int SCREEN_W = 640;
  localparam int SCREEN_H = 480;

  // Pixel clock 31.5 MHz; VGA_Controller counts 833 x 521 per frame => ~72.6 frames/s.
  localparam int CLOCKS_PER_SECOND = 31_500_000;

  // Positions are kept in 1/64 pixel, as in the supplied smiley_move.sv.
  localparam int FIXED_SHIFT = 6;

  // ---------------------------------------------------------------- bird
  localparam int BIRD_SIZE     = 32;
  localparam int BIRD_X        = 144;       // fixed horizontal position (top-left)
  localparam int BIRD_Y_MIN    = 64;        // allowed range of the sprite's top edge
  localparam int BIRD_Y_MAX    = 384;
  localparam int BIRD_Y_CENTER = 224;

  // Hitbox inside the 32x32 sprite: body only, so fins, tail and beak are forgiving.
  // Ranges are [first, last] inclusive.
  localparam int BIRD_HB_X0 = 9;
  localparam int BIRD_HB_X1 = 25;
  localparam int BIRD_HB_Y0 = 10;
  localparam int BIRD_HB_Y1 = 24;

  localparam int BIRD_FRAMES_PER_ANIM_STEP = 8;   // fin animation 0-1-2-1, ~9 steps/s

  // EASY: one sine-table step per frame (256 frames per bob, ~3.5 s), amplitude 127 px.
  localparam int EASY_PHASE_STEP = 16;            // in 1/16 table entries per frame

  // ---------------------------------------------------------------- coral columns
  localparam int NUM_COLUMNS     = 3;
  localparam int CORAL_W         = 64;            // width of the artwork
  localparam int GAP_H           = 128;           // visible opening between upper and lower coral
  localparam int GAP_CENTER_MIN  = 80;            // the opening always stays on screen
  localparam int GAP_CENTER_MAX  = 400;
  localparam int GAP_BASE_MIN    = 176;           // random opening centre (before the player's offset): 176..303
  localparam int CORAL_FIRST_X   = 480;           // left edge of the first column when a round starts
  localparam int CORAL_WRAP_W    = 720;           // a column leaving on the left re-enters this far to the right

  // Collision rectangle vs. artwork: the knobbly sides and the branch tips next to
  // the opening are decoration and never collide.
  localparam int CORAL_CORE_INSET  = 4;
  localparam int CORAL_TIP_FORGIVE = 8;

  // Player control of the shared vertical offset. MAZE_STEP_MAX must be at least
  // the bird's fastest vertical speed so the player can always keep up.
  localparam int MAZE_STEP_MAX   = 4;             // px per frame after a short hold
  localparam int MAZE_OFFSET_MAX = GAP_CENTER_MAX - GAP_BASE_MIN;

  // World scroll speed, 1/64 px per frame (SW[2:0] control arrives in M9).
  localparam int WORLD_STEP_DEFAULT = 128;        // 2.0 px per frame

  // ---------------------------------------------------------------- scenery
  localparam int SEABED_TOP = 440;                // highest row of the sand

endpackage
