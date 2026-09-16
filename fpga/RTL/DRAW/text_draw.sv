// Renders the text lines of text_pkg with the 8x8 font ROM, based on the
// supplied NumbersBitMap.sv (1-bit glyph ROM, fixed colour per object) with
// one more level of indirection: pixel -> line -> character -> glyph bit.
// All cell sizes are powers of two, so only shifts are needed. Latency: 3 clocks.

module text_draw
  import palette_pkg::*, text_pkg::*;
(
    input  logic            clk,
    input  logic            resetN,
    input  logic [10:0]     pixelX,
    input  logic [10:0]     pixelY,
    input  logic [2:0]      screen,       // game_fsm state
    input  logic [1:0]      menuCursor,
    input  logic [2:0][3:0] scoreDigits,  // BCD, [2] = hundreds
    input  logic [2:0][3:0] bestDigits,
    input  logic            newBest,
    input  logic            blink,        // slow toggle for blinking lines
    output logic            drawingRequest,
    output color_t          RGBout
);

  // ---------------------------------------------------------------- stage 0: which line
  logic [NUM_LINES-1:0] inLine;

  genvar i;
  generate
    for (i = 0; i < NUM_LINES; i++) begin : line
      // Constant wires (Quartus 17 does not accept struct fields in localparams);
      // they are folded into fixed comparisons when the design is built.
      line_t L;
      int    right, bottom;
      logic  shown;

      assign L      = line_cfg(5'(i));
      assign right  = int'(L.x) + (int'(L.length) << ({1'b0, L.scale} + 3'd3));
      assign bottom = int'(L.y) + (8 << L.scale);

      assign shown     = L.screens[screen] && (L.kind != KIND_NEW_BEST || (newBest && blink));
      assign inLine[i] = shown && pixelX >= L.x && pixelX < right && pixelY >= L.y && pixelY < bottom;
    end
  endgenerate

  logic       anyLine;
  logic [4:0] selLine;

  always_comb begin
    anyLine = 1'b0;
    selLine = '0;
    for (int k = NUM_LINES - 1; k >= 0; k--) begin
      if (inLine[k]) begin
        anyLine = 1'b1;
        selLine = 5'(k);
      end
    end
  end

  line_t sel0;
  assign sel0 = line_cfg(selLine);

  logic [4:0]  line1;
  logic [9:0]  relX1;
  logic [6:0]  relY1;
  logic        valid1;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      line1  <= '0;
      relX1  <= '0;
      relY1  <= '0;
      valid1 <= 1'b0;
    end else begin
      line1  <= selLine;
      relX1  <= 10'(pixelX - 11'(sel0.x));
      relY1  <= 7'(pixelY - 11'(sel0.y));
      valid1 <= anyLine;
    end
  end

  // ---------------------------------------------------------------- stage 1: which character and glyph pixel
  line_t      cfg;
  logic [5:0] column;
  logic [2:0] glyphX, glyphY;
  logic [7:0] code;
  logic       selected;
  color_t     color1;

  assign cfg    = line_cfg(line1);
  assign column = 6'(relX1 >> ({1'b0, cfg.scale} + 3'd3));   // 3-bit shift amount: scale + 3 reaches 6
  assign glyphX = 3'(relX1 >> cfg.scale);
  assign glyphY = 3'(relY1 >> cfg.scale);
  assign selected = (cfg.kind == KIND_ITEM) && (cfg.item == menuCursor);

  always_comb begin : pickCharacter
    int fromRight;                                  // 0 = last character of the line
    fromRight = int'(cfg.length) - 1 - int'(column);
    if (fromRight < 0) fromRight = 0;               // only happens when valid1 = 0
    code = cfg.text[fromRight * 8 +: 8];
    case (cfg.kind)
      KIND_SCORE: if (fromRight < 3) code = 8'h30 + 8'(scoreDigits[fromRight]);
      KIND_BEST:  if (fromRight < 3) code = 8'h30 + 8'(bestDigits[fromRight]);
      KIND_ITEM:  if (column == 6'd0) code = selected ? 8'h3E : 8'h20;   // '>' or ' '
      default: ;
    endcase
  end

  assign color1 = selected ? C_TEXT_GOLD : cfg.color;

  // ---------------------------------------------------------------- stage 2: font ROM, stage 3: output
  logic [11:0] address;
  logic        ink;
  logic        valid2;
  color_t      color2;

  assign address = {6'(code - 8'h20), glyphY, glyphX};

  lpm_rom #(
      .lpm_width             (1),
      .lpm_widthad           (12),
      .lpm_numwords          (4096),
      .lpm_file              ("RTL/MIF/font.mif"),
      .lpm_type              ("LPM_ROM"),
      .lpm_address_control   ("REGISTERED"),
      .lpm_outdata           ("UNREGISTERED"),
      .intended_device_family("Cyclone V")
  ) rom (
      .address(address),
      .inclock(clk),
      .q      (ink)
  );

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      valid2 <= 1'b0;
      color2 <= TRANSPARENT;
      RGBout <= TRANSPARENT;
    end else begin
      valid2 <= valid1;
      color2 <= color1;
      RGBout <= (valid2 && ink) ? color2 : TRANSPARENT;
    end
  end

  assign drawingRequest = (RGBout != TRANSPARENT);

endmodule
