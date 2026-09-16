// Project colour palette.
//
// On-screen format is RRRGGGBB: RGB[7:5] red, RGB[4:2] green, RGB[1:0] blue.
// VGA_Controller.sv labels these fields differently, but the supplied pin
// file routes them so the lab's own sprites (yellow smiley, red heart) only
// display correctly as RRRGGGBB. Blue therefore has just 4 levels
// (00, 40, BF, FF after the controller's MSB replication), so the water uses
// green/blue mixes plus dithering.

package palette_pkg;

  typedef logic [7:0] color_t;

  // 8'hFF (white) marks a transparent pixel in the supplied bitmap modules.
  localparam color_t TRANSPARENT = 8'hFF;

  //                                   red    green  blue
  localparam color_t C_BLACK       = {3'd0, 3'd0, 2'd0};
  localparam color_t C_NEAR_WHITE  = {3'd6, 3'd7, 2'd3};   // cool white; FF is reserved
  localparam color_t C_NAVY        = {3'd0, 3'd0, 2'd1};
  localparam color_t C_AMBER       = {3'd7, 3'd5, 2'd0};
  localparam color_t C_ORANGE      = {3'd7, 3'd3, 2'd0};
  localparam color_t C_CYAN        = {3'd0, 3'd6, 2'd3};

  // Water depth ramp, surface (index 0) to sea floor (index 8).
  localparam color_t C_WATER_0     = {3'd1, 3'd6, 2'd3};
  localparam color_t C_WATER_1     = {3'd0, 3'd5, 2'd3};
  localparam color_t C_WATER_2     = {3'd0, 3'd4, 2'd3};
  localparam color_t C_WATER_3     = {3'd0, 3'd3, 2'd3};
  localparam color_t C_WATER_4     = {3'd0, 3'd2, 2'd3};
  localparam color_t C_WATER_5     = {3'd0, 3'd1, 2'd2};
  localparam color_t C_WATER_6     = {3'd0, 3'd0, 2'd2};
  localparam color_t C_WATER_7     = {3'd0, 3'd0, 2'd2};   // deep water stays royal blue
  localparam color_t C_WATER_8     = {3'd0, 3'd0, 2'd1};   // only reached behind the sea floor

  // Text.
  localparam color_t C_TEXT_GOLD   = {3'd7, 3'd6, 2'd0};
  localparam color_t C_TEXT_WHITE  = C_NEAR_WHITE;
  localparam color_t C_TEXT_CYAN   = {3'd5, 3'd7, 2'd3};
  localparam color_t C_TEXT_DIM    = {3'd4, 3'd5, 2'd3};
  localparam color_t C_TEXT_RED    = {3'd7, 3'd1, 2'd1};
  localparam color_t C_TEXT_GREEN  = {3'd2, 3'd7, 2'd1};
  localparam color_t C_TEXT_GREY   = {3'd3, 3'd3, 2'd1};
  localparam color_t C_TEXT_AMBER  = {3'd7, 3'd5, 2'd0};

  // Panels.
  localparam color_t C_PANEL       = {3'd0, 3'd0, 2'd1};   // drawn on every other pixel
  localparam color_t C_BAR         = {3'd0, 3'd0, 2'd1};
  localparam color_t C_BAR_EDGE    = {3'd3, 3'd6, 2'd3};
  localparam color_t C_FLASH       = {3'd7, 3'd1, 2'd1};

  // Sea floor.
  localparam color_t C_SAND_LIGHT  = {3'd6, 3'd5, 2'd1};
  localparam color_t C_SAND        = {3'd5, 3'd4, 2'd1};
  localparam color_t C_SAND_DARK   = {3'd4, 3'd3, 2'd1};
  localparam color_t C_PEBBLE      = {3'd2, 3'd2, 2'd1};

endpackage
