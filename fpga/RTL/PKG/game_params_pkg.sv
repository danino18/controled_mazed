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

endpackage
