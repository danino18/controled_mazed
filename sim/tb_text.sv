// Checks the text table (lengths, placement, no overlaps) and text_draw
// (dynamic digits, menu cursor and highlight, screen visibility, NEW BEST).
`timescale 1ns / 1ps

module tb_text;
  import palette_pkg::*, text_pkg::*, game_state_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic [10:0]     pixelX = '0, pixelY = '0;
  logic [2:0]      screen = ST_PLAY;
  logic [1:0]      menuCursor = 2'd0;
  logic [2:0][3:0] scoreDigits = '0, bestDigits = '0;
  logic            newBest = 1'b0, blink = 1'b0;
  logic            textDR;
  color_t          textRGB;

  text_draw dut (
      .clk(clk), .resetN(resetN), .pixelX(pixelX), .pixelY(pixelY), .screen(screen),
      .menuCursor(menuCursor), .scoreDigits(scoreDigits), .bestDigits(bestDigits),
      .newBest(newBest), .blink(blink), .drawingRequest(textDR), .RGBout(textRGB));

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 15) $display("FAIL: %s", msg);
  endtask

  function automatic int cell_px(input line_t l);
    return 8 << l.scale;
  endfunction

  // Colour of one pixel (the layer has a 3-clock latency).
  task automatic sample(input int x, input int y, output color_t c);
    @(negedge clk);
    pixelX = x;
    pixelY = y;
    repeat (3) @(negedge clk);
    c = textRGB;
  endtask

  // Ink bitmap of one character cell, sampled at glyph resolution (8x8).
  task automatic glyph_at(input int lineIdx, input int column, output logic [63:0] bits, output color_t colour);
    line_t l;
    color_t c;
    l = line_cfg(5'(lineIdx));
    bits = '0;
    colour = TRANSPARENT;
    for (int gy = 0; gy < 8; gy++)
      for (int gx = 0; gx < 8; gx++) begin
        sample(l.x + column * cell_px(l) + (gx << l.scale), l.y + (gy << l.scale), c);
        if (c != TRANSPARENT) begin
          bits[gy * 8 + gx] = 1'b1;
          colour = c;
        end
      end
  endtask

  initial begin
    logic [63:0] a, b;
    color_t ca, cb;

    // ---------------------------------------------------------------- table checks
    for (int i = 0; i < NUM_LINES; i++) begin
      line_t l;
      l = line_cfg(5'(i));
      if (l.text[(l.length - 1) * 8 +: 8] == 8'h00) fail($sformatf("line %0d: text shorter than length %0d", i, l.length));
      if (l.length < MAX_CHARS && l.text[l.length * 8 +: 8] != 8'h00) fail($sformatf("line %0d: text longer than length %0d", i, l.length));
      if (l.x + l.length * cell_px(l) > 640 || l.y + cell_px(l) > 480) fail($sformatf("line %0d: off screen", i));
      if (l.screens == 0) fail($sformatf("line %0d: never visible", i));
      for (int j = 0; j < i; j++) begin
        line_t m;
        m = line_cfg(5'(j));
        if ((l.screens & m.screens) != 0 &&
            l.x < m.x + m.length * cell_px(m) && m.x < l.x + l.length * cell_px(l) &&
            l.y < m.y + cell_px(m) && m.y < l.y + cell_px(l))
          fail($sformatf("lines %0d and %0d overlap", i, j));
      end
    end

    repeat (2) @(negedge clk);
    resetN = 1'b1;

    // ---------------------------------------------------------------- dynamic digits (HUD lines 11 and 12)
    screen = ST_PLAY;
    scoreDigits = {4'd7, 4'd8, 4'd9};
    bestDigits  = {4'd7, 4'd8, 4'd9};
    for (int k = 6; k < 9; k++) begin
      glyph_at(11, k, a, ca);
      glyph_at(12, k, b, cb);
      if (a != b || a == 0) fail($sformatf("HUD digit %0d differs between SCORE and BEST", k));
    end
    glyph_at(11, 8, a, ca);
    scoreDigits = {4'd7, 4'd8, 4'd1};
    glyph_at(11, 8, b, cb);
    if (a == b) fail("score digit did not change the rendered glyph");
    glyph_at(11, 5, a, ca);                        // the space before the digits
    if (a != 0) fail("space rendered ink");
    glyph_at(11, 0, a, ca);                        // 'S'
    if (a == 0 || ca != C_TEXT_WHITE) fail("SCORE label missing or wrong colour");

    // ---------------------------------------------------------------- visibility
    glyph_at(0, 0, a, ca);                         // menu title hidden while playing
    if (a != 0) fail("menu title visible during play");
    screen = ST_MENU_DIFF;
    glyph_at(0, 0, a, ca);
    if (a == 0) fail("menu title missing on the difficulty menu");
    glyph_at(11, 0, a, ca);
    if (a != 0) fail("HUD visible in the menu");
    glyph_at(8, 0, a, ca);                         // obstacle menu cursor slot, not covered by any difficulty-menu line
    if (a != 0) fail("obstacle menu visible on the difficulty menu");

    // ---------------------------------------------------------------- cursor and highlight
    for (int cur = 0; cur < 3; cur++) begin
      menuCursor = 2'(cur);
      for (int item = 0; item < 3; item++) begin
        glyph_at(4 + item, 0, a, ca);
        glyph_at(4 + item, 2, b, cb);              // first letter of the item
        if ((item == cur) != (a != 0)) fail($sformatf("cursor %0d: marker on item %0d = %b", cur, item, a != 0));
        if ((item == cur) != (cb == C_TEXT_GOLD)) fail($sformatf("cursor %0d: item %0d colour %h", cur, item, cb));
      end
    end

    // ---------------------------------------------------------------- NEW BEST blinks only after a new best
    screen = ST_GAME_OVER;
    newBest = 1'b0; blink = 1'b1;
    glyph_at(19, 0, a, ca);
    if (a != 0) fail("NEW BEST shown without a new best");
    newBest = 1'b1; blink = 1'b1;
    glyph_at(19, 0, a, ca);
    if (a == 0) fail("NEW BEST missing");
    blink = 1'b0;
    glyph_at(19, 0, a, ca);
    if (a != 0) fail("NEW BEST does not blink");

    if (errors == 0) $display("PASS: tb_text");
    else             $display("FAIL: tb_text (%0d errors)", errors);
    $finish;
  end

endmodule
