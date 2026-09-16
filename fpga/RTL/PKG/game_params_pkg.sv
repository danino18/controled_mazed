// Tunable game constants shared by logic and drawing modules.

package game_params_pkg;

  localparam int SCREEN_W = 640;
  localparam int SCREEN_H = 480;

  // Pixel clock 31.5 MHz; VGA_Controller counts 833 x 521 per frame => ~72.6 frames/s.
  localparam int CLOCKS_PER_SECOND = 31_500_000;

  localparam int BIRD_SIZE = 32;
  localparam int BIRD_X    = 144;                          // fixed horizontal position
  localparam int BIRD_Y0   = (SCREEN_H - BIRD_SIZE) / 2;   // start height

endpackage
