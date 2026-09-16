// Text-screen layer: menus, AI overlays and (from M10) the training screen.
//
// A screen ("page") is an 80x60 grid of cells (8x8 px) or a 40x30 grid
// (16x16 px), each cell {panel, colour, glyph}. Pages are authored in
// assets/screens/screens.txt and converted by tools/screen_tool.tcl into:
//   pages.mif   the static text of every page
//   fields.mif  where the dynamic values go and how they are formatted
//   words.mif   word lists selected by a value (e.g. UP / HOLD / DOWN)
//
// On a page change the page is copied into a character RAM (about 10,000
// clocks) and the layer stays hidden until the next frame starts. Once per
// frame, during vertical blanking, the writer formats every dynamic value of
// the page and writes it into the character RAM (well under 3,000 clocks for
// a full page of fields, far less than the ~33,000 clocks of blanking), so
// every visible frame shows one consistent set of values.
//
// Rendering follows the supplied NumbersBitMap idea with one more lookup:
// pixel -> cell -> glyph bit. Latency: 3 clocks, like every drawing layer.

module char_screen
  import palette_pkg::*, ui_pkg::*;
(
    input  logic                         clk,
    input  logic                         resetN,
    input  logic [10:0]                  pixelX,
    input  logic [10:0]                  pixelY,
    input  logic                         startOfFrame,
    input  logic [3:0]                   page,          // PAGE_NONE hides the layer
    input  logic [NUM_SOURCES-1:0][31:0] sources,
    output logic                         drawingRequest,
    output color_t                       RGBout,
    output logic                         shown,         // the requested page is on screen
    output logic                         writerIdle     // for tests: no load or field pass running
);

  localparam int CELLS   = PAGE_CELLS;
  localparam int PAGE_AW = $clog2(PAGE_WORDS);   // the ROM model wants exactly this width

  // ================================================================ memories
  // page ROM: address registered, output not
  logic [15:0] pRomAddr;
  logic [9:0]  pRomQ;

  lpm_rom #(
      .lpm_width             (10),
      .lpm_widthad           (PAGE_AW),
      .lpm_numwords          (PAGE_WORDS),
      .lpm_file              ("RTL/MIF/pages.mif"),
      .lpm_type              ("LPM_ROM"),
      .lpm_address_control   ("REGISTERED"),
      .lpm_outdata           ("UNREGISTERED"),
      .intended_device_family("Cyclone V")
  ) pageRom (
      .address(pRomAddr[PAGE_AW-1:0]),
      .inclock(clk),
      .q      (pRomQ)
  );

  logic [7:0]  fRomAddr;
  logic [42:0] fRomQ;

  lpm_rom #(
      .lpm_width             (43),
      .lpm_widthad           (8),
      .lpm_numwords          (MAX_FIELDS),
      .lpm_file              ("RTL/MIF/fields.mif"),
      .lpm_type              ("LPM_ROM"),
      .lpm_address_control   ("REGISTERED"),
      .lpm_outdata           ("UNREGISTERED"),
      .intended_device_family("Cyclone V")
  ) fieldRom (
      .address(fRomAddr),
      .inclock(clk),
      .q      (fRomQ)
  );

  logic [6:0]  wRomAddr;
  logic [50:0] wRomQ;

  lpm_rom #(
      .lpm_width             (51),
      .lpm_widthad           (7),
      .lpm_numwords          (MAX_WORDS),
      .lpm_file              ("RTL/MIF/words.mif"),
      .lpm_type              ("LPM_ROM"),
      .lpm_address_control   ("REGISTERED"),
      .lpm_outdata           ("UNREGISTERED"),
      .intended_device_family("Cyclone V")
  ) wordRom (
      .address(wRomAddr),
      .inclock(clk),
      .q      (wRomQ)
  );

  // character RAM (inferred M10K): one write port, one read port for the renderer
  logic        ramWe;
  logic [12:0] ramWa;
  logic [9:0]  ramWd;
  logic [12:0] ramRa;
  logic [12:0] ramRaReg;
  logic [9:0]  ramQ;
  // Quartus adds read-during-write pass-through logic (warning 276020); it is
  // harmless here and the attribute to drop it is not honoured by Quartus 17.
  logic [9:0]  charRam [0:CELLS-1];

  always_ff @(posedge clk) begin
    if (ramWe) charRam[ramWa] <= ramWd;
    ramRaReg <= ramRa;
  end

  assign ramQ = charRam[ramRaReg];

  // ================================================================ loader and field writer
  function automatic logic [15:0] page_base(input logic [3:0] p);
    return 16'((int'(p) - 1) * CELLS);
  endfunction

  function automatic logic [12:0] row_base(input logic [5:0] r);
    return {1'b0, r, 6'b0} + {3'b0, r, 4'b0};     // r * 80
  endfunction

  localparam logic [5:0] G_SPACE = 6'h00;
  localparam logic [5:0] G_BLOCK = 6'h03;   // '#' is drawn as a solid block
  localparam logic [5:0] G_PLUS  = 6'h0B;
  localparam logic [5:0] G_MINUS = 6'h0D;
  localparam logic [5:0] G_ZERO  = 6'h10;
  localparam logic [5:0] G_GT    = 6'h1E;
  localparam logic [5:0] G_A     = 6'h21;
  localparam logic [2:0] COL_GOLD = 3'd1;

  typedef enum logic [3:0] {
      S_IDLE, S_LOAD, S_LOAD_LAST, S_F_ADDR, S_F_READ, S_F_DISPATCH, S_BCD,
      S_WORD_READ, S_WRITE, S_CUR_ADDR, S_CUR_WRITE, S_F_NEXT
  } state_t;

  state_t      state;
  logic        shownReg;       // curPage is visible (changes only at a frame start)
  logic [3:0]  curPage;        // page held in the character RAM
  logic [3:0]  loadPage;
  logic        ready;          // curPage is complete (loaded and one field pass written)
  logic        frameReq;
  logic [12:0] loadCount;
  logic        loadValid1;
  logic [12:0] loadWa1;

  // current field
  logic [7:0]  idx;
  logic [3:0]  fPage;
  logic [5:0]  fRow;
  logic [6:0]  fCol;
  logic [3:0]  fLen;
  logic [2:0]  fFmt;
  logic [6:0]  fArg;
  logic [3:0]  fAttr;
  logic [31:0] value;
  logic [31:0] mag;
  logic        neg;
  logic        sat;
  logic        cursorSel;
  logic [39:0] bcd;
  logic [31:0] bin;
  logic [5:0]  iter;
  logic [50:0] word;
  logic [3:0]  k;
  logic        leadingDone;    // DECB: a non-zero digit has been written
  logic [12:0] fieldBase;      // row * 80 + col

  // largest value that fits the digits of the current field, plus one
  logic [3:0]  digitCount;
  logic [31:0] digitLimit;

  always_comb begin
    digitCount = (fFmt == FMT_SDEC) ? fLen - 4'd1 : fLen;
    case (digitCount)
      4'd1:    digitLimit = 32'd10;
      4'd2:    digitLimit = 32'd100;
      4'd3:    digitLimit = 32'd1000;
      4'd4:    digitLimit = 32'd10000;
      4'd5:    digitLimit = 32'd100000;
      4'd6:    digitLimit = 32'd1000000;
      4'd7:    digitLimit = 32'd10000000;
      4'd8:    digitLimit = 32'd100000000;
      default: digitLimit = 32'd1000000000;
    endcase
  end

  // BCD digit adjust (add 3 to every digit >= 5) before each shift
  logic [39:0] bcdAdj;
  always_comb begin
    for (int d = 0; d < 10; d++)
      bcdAdj[d * 4 +: 4] = (bcd[d * 4 +: 4] >= 4'd5) ? bcd[d * 4 +: 4] + 4'd3 : bcd[d * 4 +: 4];
  end

  // the glyph and attribute of cell k of the current field
  logic [3:0]  pos;
  logic [3:0]  digit;
  logic [3:0]  nibble;
  logic [5:0]  cellGlyph;
  logic [3:0]  cellAttr;
  logic        isLast;

  always_comb begin
    pos      = fLen - 4'd1 - k;
    digit    = sat ? 4'd9 : bcd[pos * 4 +: 4];
    nibble   = value[pos * 4 +: 4];
    isLast   = (k == fLen - 4'd1);
    cellAttr = fAttr;
    case (fFmt)
      FMT_DEC:  cellGlyph = G_ZERO + 6'(digit);
      FMT_DECB: cellGlyph = (!leadingDone && digit == 4'd0 && !isLast) ? G_SPACE : G_ZERO + 6'(digit);
      FMT_SDEC: cellGlyph = (k == 4'd0) ? (neg ? G_MINUS : G_PLUS) : G_ZERO + 6'(digit);
      FMT_HEX:  cellGlyph = (nibble < 4'd10) ? G_ZERO + 6'(nibble) : G_A + 6'(nibble - 4'd10);
      FMT_WORD: begin
        cellGlyph = (k < 4'd8) ? word[47 - 6 * k -: 6] : G_SPACE;
        cellAttr  = {fAttr[3], word[50:48]};
      end
      FMT_BAR:  cellGlyph = (32'(k) < value) ? G_BLOCK : G_MINUS;
      default:  cellGlyph = cursorSel ? G_GT : G_SPACE;   // CURSOR marker cell
    endcase
  end

  // value of the field's source, looked up straight from the field ROM output
  logic [7:0] romSrc;
  assign romSrc = fRomQ[18:11];

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      state       <= S_IDLE;
      curPage     <= PAGE_NONE;
      loadPage    <= PAGE_NONE;
      ready       <= 1'b0;
      shownReg    <= 1'b0;
      frameReq    <= 1'b0;
      loadCount   <= '0;
      loadValid1  <= 1'b0;
      loadWa1     <= '0;
      idx         <= '0;
      {fPage, fRow, fCol, fLen, fFmt, fArg, fAttr} <= '0;
      value       <= '0;
      mag         <= '0;
      neg         <= 1'b0;
      sat         <= 1'b0;
      cursorSel   <= 1'b0;
      bcd         <= '0;
      bin         <= '0;
      iter        <= '0;
      word        <= '0;
      k           <= '0;
      leadingDone <= 1'b0;
      fieldBase   <= '0;
    end else begin
      loadValid1 <= (state == S_LOAD);
      loadWa1    <= loadCount;

      if (startOfFrame) begin
        frameReq <= 1'b1;
        shownReg <= ready && curPage == page && page != PAGE_NONE;   // appear only on a frame boundary
      end

      case (state)
        S_IDLE: begin
          if (page != curPage) begin
            ready    <= 1'b0;
            shownReg <= 1'b0;
            if (page == PAGE_NONE) begin
              curPage <= PAGE_NONE;
            end else begin
              loadPage  <= page;
              loadCount <= '0;
              state     <= S_LOAD;
            end
          end else if (frameReq && curPage != PAGE_NONE) begin
            frameReq <= 1'b0;
            idx      <= '0;
            state    <= S_F_ADDR;
          end
        end

        S_LOAD: begin
          loadCount <= loadCount + 13'd1;
          if (loadCount == 13'(CELLS - 1)) state <= S_LOAD_LAST;
        end

        S_LOAD_LAST: begin           // the last cell is written on this clock
          curPage <= loadPage;
          idx     <= '0;
          state   <= S_F_ADDR;
        end

        S_F_ADDR: state <= S_F_READ;

        S_F_READ: begin
          {fPage, fRow, fCol, fLen, fFmt} <= fRomQ[42:19];
          fArg  <= fRomQ[10:4];
          fAttr <= fRomQ[3:0];
          value <= (int'(romSrc) < NUM_SOURCES) ? sources[romSrc] : 32'd0;
          state <= S_F_DISPATCH;
        end

        S_F_DISPATCH: begin
          k           <= '0;
          leadingDone <= 1'b0;
          fieldBase   <= row_base(fRow) + 13'(fCol);
          if (fPage != curPage || fLen == 4'd0) begin
            state <= S_F_NEXT;
          end else begin
            case (fFmt)
              FMT_DEC, FMT_DECB, FMT_SDEC: begin
                neg  <= (fFmt == FMT_SDEC) && value[31];
                mag  <= ((fFmt == FMT_SDEC) && value[31]) ? -value : value;
                bcd  <= '0;
                bin  <= ((fFmt == FMT_SDEC) && value[31]) ? -value : value;
                iter <= '0;
                state <= S_BCD;
              end
              FMT_HEX, FMT_BAR: begin
                sat   <= 1'b0;
                state <= S_WRITE;
              end
              FMT_WORD: state <= S_WORD_READ;
              default: begin                      // CURSOR
                cursorSel <= (value == 32'(fArg));
                sat       <= 1'b0;
                state     <= S_WRITE;
              end
            endcase
          end
        end

        S_BCD: begin
          if (iter == 6'd0) sat <= mag >= digitLimit;
          {bcd, bin} <= {bcdAdj[38:0], bin, 1'b0};
          iter       <= iter + 6'd1;
          if (iter == 6'd31) state <= S_WRITE;
        end

        S_WORD_READ: begin
          word  <= wRomQ;
          sat   <= 1'b0;
          state <= S_WRITE;
        end

        S_WRITE: begin
          if (cellGlyph != G_SPACE && cellGlyph != G_ZERO) leadingDone <= 1'b1;
          k <= k + 4'd1;
          if (fFmt == FMT_CURSOR) state <= (fLen == 4'd1) ? S_F_NEXT : S_CUR_ADDR;
          else if (isLast)        state <= S_F_NEXT;
        end

        S_CUR_ADDR: state <= S_CUR_WRITE;

        S_CUR_WRITE: begin
          k <= k + 4'd1;
          state <= isLast ? S_F_NEXT : S_CUR_ADDR;
        end

        S_F_NEXT: begin
          idx <= idx + 8'd1;
          if (idx == 8'(MAX_FIELDS - 1)) begin
            ready <= (curPage == page);
            state <= S_IDLE;
          end else begin
            state <= S_F_ADDR;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

  // ROM addresses (all registered inside the ROMs)
  always_comb begin
    // only address the page ROM while it is being read (the simulation model
    // of lpm_rom stops on an address past its last word)
    if (state == S_LOAD)          pRomAddr = page_base(loadPage) + 16'(loadCount);
    else if (state == S_CUR_ADDR) pRomAddr = page_base(curPage) + 16'(fieldBase) + 16'(k);
    else                          pRomAddr = 16'd0;
    fRomAddr = idx;
    wRomAddr = fArg + value[6:0];
  end

  // character RAM writes
  always_comb begin
    ramWe = 1'b0;
    ramWa = loadWa1;
    ramWd = pRomQ;
    if (loadValid1) begin
      ramWe = 1'b1;
    end else if (state == S_WRITE) begin
      ramWe = 1'b1;
      ramWa = fieldBase + 13'(k);
      ramWd = {cellAttr, cellGlyph};
    end else if (state == S_CUR_WRITE) begin
      ramWe = 1'b1;
      ramWa = fieldBase + 13'(k);
      ramWd = {pRomQ[9], cursorSel ? COL_GOLD : pRomQ[8:6], pRomQ[5:0]};
    end
  end

  assign writerIdle = (state == S_IDLE) && !frameReq && page == curPage;

  // ================================================================ renderer
  logic       scale2;
  logic [5:0] row;
  logic [6:0] col;
  logic [2:0] gx, gy;
  logic       inArea;

  assign scale2 = PAGE_SCALE2[curPage];
  assign row    = scale2 ? 6'(pixelY[9:4]) : 6'(pixelY[8:3]);
  assign col    = scale2 ? 7'(pixelX[9:4]) : 7'(pixelX[9:3]);
  assign gx     = scale2 ? pixelX[3:1] : pixelX[2:0];
  assign gy     = scale2 ? pixelY[3:1] : pixelY[2:0];
  assign shown  = shownReg && page == curPage;
  assign inArea = shown && pixelX < 11'd640 && pixelY < 11'd480;
  assign ramRa  = row_base(row) + 13'(col);

  logic       valid1, valid2;
  logic [2:0] gx1, gy1;
  logic       dither1, dither2;
  logic       panel2;
  color_t     colour2;
  logic       ink;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      valid1  <= 1'b0;
      gx1     <= '0;
      gy1     <= '0;
      dither1 <= 1'b0;
    end else begin
      valid1  <= inArea;
      gx1     <= gx;
      gy1     <= gy;
      dither1 <= pixelX[0] ^ pixelY[0];
    end
  end

  color_t colourNow;

  always_comb begin
    case (ramQ[8:6])
      3'd0:    colourNow = C_TEXT_WHITE;
      3'd1:    colourNow = C_TEXT_GOLD;
      3'd2:    colourNow = C_TEXT_CYAN;
      3'd3:    colourNow = C_TEXT_DIM;
      3'd4:    colourNow = C_TEXT_RED;
      3'd5:    colourNow = C_TEXT_GREEN;
      3'd6:    colourNow = C_TEXT_GREY;
      default: colourNow = C_TEXT_AMBER;
    endcase
  end

  lpm_rom #(
      .lpm_width             (1),
      .lpm_widthad           (12),
      .lpm_numwords          (4096),
      .lpm_file              ("RTL/MIF/font.mif"),
      .lpm_type              ("LPM_ROM"),
      .lpm_address_control   ("REGISTERED"),
      .lpm_outdata           ("UNREGISTERED"),
      .intended_device_family("Cyclone V")
  ) fontRom (
      .address({ramQ[5:0], gy1, gx1}),
      .inclock(clk),
      .q      (ink)
  );

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      valid2  <= 1'b0;
      dither2 <= 1'b0;
      panel2  <= 1'b0;
      colour2 <= TRANSPARENT;
      RGBout  <= TRANSPARENT;
    end else begin
      valid2  <= valid1;
      dither2 <= dither1;
      panel2  <= ramQ[9];
      colour2 <= colourNow;
      if (!valid2)                 RGBout <= TRANSPARENT;
      else if (ink)                RGBout <= colour2;
      else if (panel2 && dither2)  RGBout <= C_PANEL;
      else                         RGBout <= TRANSPARENT;
    end
  end

  assign drawingRequest = (RGBout != TRANSPARENT);

endmodule
