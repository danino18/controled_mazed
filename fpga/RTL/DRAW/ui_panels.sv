// Screen furniture behind the text: translucent dark panels (a one-pixel
// checkerboard of navy that darkens whatever is behind it), a button-style
// bar behind the selected menu entry, and a red flash right after a crash.
// Latency: 3 clocks, like every drawing layer.

module ui_panels
  import palette_pkg::*, game_state_pkg::*;
(
    input  logic        clk,
    input  logic        resetN,
    input  logic [10:0] pixelX,
    input  logic [10:0] pixelY,
    input  logic [2:0]  screen,
    input  logic [1:0]  menuCursor,
    input  logic        flash,
    output logic        drawingRequest,
    output color_t      RGBout
);

  function automatic logic in_rect(input logic [10:0] x, input logic [10:0] y,
                                   input int x0, input int y0, input int x1, input int y1);
    return int'(x) >= x0 && int'(x) < x1 && int'(y) >= y0 && int'(y) < y1;
  endfunction

  logic dither;
  logic tint;
  logic barFill, barEdge;
  int   barLeft, barRight, barTop;
  logic inMenu;

  assign dither  = pixelX[0] ^ pixelY[0];
  assign inMenu  = (screen == ST_MENU_DIFF) || (screen == ST_MENU_OBST);

  // Selected-entry bar: menu entries are 48 px apart.
  always_comb begin
    if (screen == ST_GAME_OVER) begin
      barLeft  = 168;
      barRight = 544;
      barTop   = 260 + 48 * int'(menuCursor);
    end else begin
      barLeft  = 200;
      barRight = 568;
      barTop   = 164 + 48 * int'(menuCursor);
    end
  end

  always_comb begin
    tint    = 1'b0;
    barFill = 1'b0;
    barEdge = 1'b0;
    if (inMenu || screen == ST_GAME_OVER) begin
      barFill = in_rect(pixelX, pixelY, barLeft, barTop, barRight, barTop + 40);
      barEdge = barFill && !in_rect(pixelX, pixelY, barLeft + 2, barTop + 2, barRight - 2, barTop + 38);
    end
    case (screen)
      ST_MENU_DIFF, ST_MENU_OBST:
        tint = in_rect(pixelX, pixelY, 64, 32, 576, 80) ||      // title
               in_rect(pixelX, pixelY, 176, 100, 592, 324) ||   // subtitle and entries
               in_rect(pixelX, pixelY, 64, 388, 576, 444);      // best score and hint
      ST_READY:
        tint = in_rect(pixelX, pixelY, 176, 104, 592, 204) ||
               in_rect(pixelX, pixelY, 480, 4, 636, 50);
      ST_PLAY, ST_HIT:
        tint = in_rect(pixelX, pixelY, 480, 4, 636, 50);
      ST_GAME_OVER:
        tint = in_rect(pixelX, pixelY, 16, 28, 624, 356);
      default: tint = 1'b0;
    endcase
  end

  color_t stage1, stage2;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      stage1 <= TRANSPARENT;
      stage2 <= TRANSPARENT;
      RGBout <= TRANSPARENT;
    end else begin
      if (barEdge)                 stage1 <= C_BAR_EDGE;
      else if (barFill)            stage1 <= C_BAR;
      else if (flash && dither)    stage1 <= C_FLASH;
      else if (tint && dither)     stage1 <= C_PANEL;
      else                         stage1 <= TRANSPARENT;
      stage2 <= stage1;
      RGBout <= stage2;
    end
  end

  assign drawingRequest = (RGBout != TRANSPARENT);

endmodule
