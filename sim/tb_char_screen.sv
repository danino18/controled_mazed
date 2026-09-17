// Text-screen layer (char_screen) against a reference model that reads the
// same generated .mif files:
//
//   - after every page load and every frame's field pass, all 4,800 cells of
//     the character RAM equal the page text with the fields formatted by the
//     model (DEC, DECB, SDEC, HEX, WORD, CURSOR), for random and extreme values
//   - a few cells are also checked against literal strings, so the model
//     itself is tested
//   - every visible pixel of the rendered frame equals the model's rendering
//     (glyph bits, colours, dark panels, 8x8 and 16x16 pages)
//   - the layer stays hidden from a page change until the new page is
//     complete, and it only appears at the start of a frame
//   - the field pass ends before the first visible line
`timescale 1ns / 1ps

module tb_char_screen;
  import palette_pkg::*, ui_pkg::*, ml_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #15.873 clk = ~clk;

  logic [10:0] pixelX, pixelY;
  logic        startOfFrame;
  logic [28:0] ovga;
  color_t      rgb;

  VGA_Controller vga (
      .RGBIn(8'h00), .PixelX(pixelX), .PixelY(pixelY), .startOfFrame(startOfFrame),
      .oVGA(ovga), .address(), .clk(clk), .resetN(resetN));

  logic [3:0]                   page = PAGE_NONE;
  logic [NUM_SOURCES-1:0][31:0] sources = '0;
  logic                         drawingRequest, shown, writerIdle;

  char_screen dut (
      .clk(clk), .resetN(resetN), .pixelX(pixelX), .pixelY(pixelY), .startOfFrame(startOfFrame),
      .page(page), .sources(sources), .drawingRequest(drawingRequest), .RGBout(rgb),
      .shown(shown), .writerIdle(writerIdle));

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 25) $display("FAIL: %s", msg);
  endtask

  // ---------------------------------------------------------------- .mif reader
  task automatic load_mif(input string path, ref logic [63:0] mem [], output int depth);
    int fd, a, n;
    string line;
    bit inContent, addrHex, dataBin;
    logic [63:0] d;
    fd = $fopen(path, "r");
    if (fd == 0) begin
      fail($sformatf("cannot open %s", path));
      depth = 0;
      return;
    end
    inContent = 0; addrHex = 0; dataBin = 0; depth = 0;
    while (!$feof(fd)) begin
      void'($fgets(line, fd));
      if (!inContent) begin
        if ($sscanf(line, "DEPTH = %d;", n) == 1) begin
          depth = n;
          mem = new[n];
          foreach (mem[i]) mem[i] = '0;
        end
        if (line.substr(0, 12) == "ADDRESS_RADIX") addrHex = (line.substr(16, 18) == "HEX");
        if (line.substr(0, 9) == "DATA_RADIX") dataBin = (line.substr(13, 15) == "BIN");
        if (line.substr(0, 12) == "CONTENT BEGIN") inContent = 1;
      end else begin
        int ok;
        if (addrHex) ok = $sscanf(line, "%h :", a);
        else         ok = $sscanf(line, "%d :", a);
        if (ok == 1) begin
          int colon;
          string rest;
          colon = 0;
          while (colon < line.len() && line[colon] != ":") colon++;
          rest = line.substr(colon + 1, line.len() - 1);
          if (dataBin) void'($sscanf(rest, "%b", d));
          else         void'($sscanf(rest, "%h", d));
          mem[a] = d;
        end
      end
    end
    $fclose(fd);
  endtask

  logic [63:0] pageRom [];
  logic [63:0] fieldRom [];
  logic [63:0] wordRom [];
  logic [63:0] fontRom [];

  // ---------------------------------------------------------------- reference model
  logic [9:0] model [PAGE_CELLS];

  function automatic logic [5:0] glyph_of(input byte c);
    return 6'(c - 8'h20);
  endfunction

  function automatic int pow10i(input int n);
    int p;
    p = 1;
    repeat (n) p *= 10;
    return p;
  endfunction

  function automatic string digits_of(input longint v, input int n, input bit blanks);
    string s;
    longint m;
    s = "";
    if (v >= pow10i(n)) begin
      repeat (n) s = {s, "9"};
      return s;
    end
    m = v;
    for (int i = 0; i < n; i++) begin
      s = {$sformatf("%0d", m % 10), s};
      m /= 10;
    end
    if (blanks)
      for (int i = 0; i < n - 1 && s[i] == "0"; i++) s[i] = " ";
    return s;
  endfunction

  task automatic build_model(input int p);
    for (int c = 0; c < PAGE_CELLS; c++) model[c] = pageRom[(p - 1) * PAGE_CELLS + c][9:0];
    for (int f = 0; f < MAX_FIELDS; f++) begin
      logic [42:0] e;
      int fp, row, col, len, fmt, src, arg, attr, base;
      longint unsigned v;
      string text;
      e    = fieldRom[f][42:0];
      fp   = e[42:39]; row = e[38:33]; col = e[32:26]; len = e[25:22];
      fmt  = e[21:19]; src = e[18:11]; arg = e[10:4];  attr = e[3:0];
      if (fp != p || len == 0) continue;
      base = row * 80 + col;
      v    = sources[src];
      case (fmt)
        FMT_DEC, FMT_DECB: begin
          text = digits_of(v, len, fmt == FMT_DECB);
          for (int k = 0; k < len; k++) model[base + k] = {4'(attr), glyph_of(text[k])};
        end
        FMT_SDEC: begin
          int sv;
          sv   = int'(v[31:0]);
          text = {sv < 0 ? "-" : "+", digits_of(sv < 0 ? -longint'(sv) : sv, len - 1, 0)};
          for (int k = 0; k < len; k++) model[base + k] = {4'(attr), glyph_of(text[k])};
        end
        FMT_HEX: begin
          for (int k = 0; k < len; k++) begin
            int nib;
            nib = (v >> (4 * (len - 1 - k))) & 15;
            model[base + k] = {4'(attr), glyph_of(nib < 10 ? 8'h30 + nib : 8'h41 + nib - 10)};
          end
        end
        FMT_WORD: begin
          logic [50:0] w;
          w = wordRom[(arg + (v & 127)) & 127][50:0];
          for (int k = 0; k < len; k++)
            model[base + k] = {attr[3], w[50:48], (k < 8) ? w[47 - 6 * k -: 6] : 6'd0};
        end
        FMT_CURSOR: begin
          bit sel;
          sel = (v == arg);
          model[base] = {4'(attr), sel ? glyph_of(">") : 6'd0};
          for (int k = 1; k < len; k++) begin
            logic [9:0] pc;
            pc = pageRom[(p - 1) * PAGE_CELLS + base + k][9:0];
            model[base + k] = {pc[9], sel ? 3'd1 : pc[8:6], pc[5:0]};
          end
        end
        FMT_BAR: begin
          for (int k = 0; k < len; k++) model[base + k] = {4'(attr), k < v ? 6'h03 : glyph_of("-")};
        end
        default: fail($sformatf("field %0d has unknown format %0d", f, fmt));
      endcase
    end
  endtask

  task automatic check_ram(input string what);
    int bad;
    bad = 0;
    for (int c = 0; c < PAGE_CELLS; c++)
      if (dut.charRam[c] !== model[c]) begin
        bad++;
        if (bad <= 3)
          fail($sformatf("%s: cell row %0d col %0d = %03h, expected %03h", what, c / 80, c % 80,
                         dut.charRam[c], model[c]));
      end
    if (bad > 3) fail($sformatf("%s: %0d cells differ", what, bad));
  endtask

  // the text of a cell range as ASCII (for literal checks)
  function automatic string cells_text(input int row, input int col, input int len);
    string s;
    s = "";
    for (int k = 0; k < len; k++) s = {s, $sformatf("%c", 8'h20 + dut.charRam[row * 80 + col + k][5:0])};
    return s;
  endfunction

  function automatic color_t palette_of(input logic [2:0] c);
    case (c)
      3'd0: return C_TEXT_WHITE;  3'd1: return C_TEXT_GOLD;
      3'd2: return C_TEXT_CYAN;   3'd3: return C_TEXT_DIM;
      3'd4: return C_TEXT_RED;    3'd5: return C_TEXT_GREEN;
      3'd6: return C_TEXT_GREY;   default: return C_TEXT_AMBER;
    endcase
  endfunction

  function automatic color_t expected_pixel(input int p, input int x, input int y);
    bit s2;
    int row, col, gx, gy;
    logic [9:0] v;
    bit ink;
    s2  = PAGE_SCALE2[p];
    row = s2 ? y >> 4 : y >> 3;
    col = s2 ? x >> 4 : x >> 3;
    gx  = s2 ? (x & 15) >> 1 : x & 7;
    gy  = s2 ? (y & 15) >> 1 : y & 7;
    v   = model[row * 80 + col];
    ink = fontRom[{v[5:0], 3'(gy), 3'(gx)}][0];
    if (ink) return palette_of(v[8:6]);
    if (v[9] && ((x ^ y) & 1)) return C_PANEL;
    return TRANSPARENT;
  endfunction

  // ---------------------------------------------------------------- pixel checking
  // RGBout belongs to the pixel coordinates of 3 clocks earlier (xd/yd/vd below).
  logic [10:0] xd [3];
  logic [10:0] yd [3];
  logic        vd [3];
  bit          checkPixels = 0;
  bit          expectHidden = 0;
  int          checkedPixels = 0;
  int          checkPage = 0;

  always @(posedge clk) begin
    if (resetN) begin
      if (checkPixels && vd[2]) begin
        color_t e;
        e = expected_pixel(checkPage, xd[2], yd[2]);
        checkedPixels++;
        if (rgb !== e) fail($sformatf("page %0d pixel (%0d,%0d) = %02h, expected %02h", checkPage, xd[2], yd[2], rgb, e));
      end
      if (expectHidden && drawingRequest) fail("the layer drew while its page was not ready");
    end
  end

  // shift register of {x, y, visible}
  always @(posedge clk) begin
    xd[0] <= pixelX;  yd[0] <= pixelY;  vd[0] <= ovga[27] && pixelX < 640 && pixelY < 480;
    xd[1] <= xd[0];   yd[1] <= yd[0];   vd[1] <= vd[0];
    xd[2] <= xd[1];   yd[2] <= yd[1];   vd[2] <= vd[1];
  end

  task automatic wait_frame();
    @(posedge clk iff startOfFrame);
  endtask

  // Waits until the current page's field pass after the next frame start is written.
  int passClocks;
  int worstPass = 0;
  task automatic next_frame_written();
    wait_frame();
    passClocks = 0;
    @(posedge clk);
    while (!writerIdle) begin
      @(posedge clk);
      passClocks++;
    end
    if (passClocks > worstPass) worstPass = passClocks;
    if (!(vga.V_Cont < 40)) fail($sformatf("field pass ended on line %0d (visible area)", vga.V_Cont));
  endtask

  task automatic randomize_sources(input int seed, input bit extreme);
    for (int s = 0; s < NUM_SOURCES; s++) begin
      logic [31:0] r;
      r = $urandom(seed + s * 7919);
      case (r[2:0])
        3'd0: sources[s] = r[1:0];                       // small (valid for words and cursors)
        3'd1: sources[s] = r % 1000;
        3'd2: sources[s] = -(r % 100000);
        3'd3: sources[s] = extreme ? 32'h7FFFFFFF : r;
        3'd4: sources[s] = extreme ? 32'h80000000 : r % 10;
        default: sources[s] = r[2:0] % 3;
      endcase
    end
  endtask

  task automatic show_page(input int p, input string what);
    page = 4'(p);
    checkPixels = 0;
    repeat (4) @(posedge clk);          // pixels already in the 3-clock pipeline
    if (shown) fail("still shown after a page change");
    expectHidden = 1;
    @(posedge clk iff shown);
    expectHidden = 0;
    build_model(p);
    check_ram({what, " after load"});
    // the whole visible part of this frame
    checkPage = p;
    checkPixels = 1;
    wait_frame();
    checkPixels = 0;
  endtask

  initial begin
    int d;
    load_mif("RTL/MIF/pages.mif", pageRom, d);
    if (d != PAGE_WORDS) fail($sformatf("pages.mif depth %0d, expected %0d", d, PAGE_WORDS));
    load_mif("RTL/MIF/fields.mif", fieldRom, d);
    load_mif("RTL/MIF/words.mif", wordRom, d);
    load_mif("RTL/MIF/font.mif", fontRom, d);

    repeat (5) @(posedge clk);
    resetN = 1'b1;

    // nothing is drawn without a page
    expectHidden = 1;
    wait_frame();
    wait_frame();
    expectHidden = 0;

    for (int p = 1; p <= NUM_PAGES; p++) begin
      randomize_sources(p * 101, 0);
      show_page(p, $sformatf("page %0d", p));
      for (int round = 0; round < 2; round++) begin
        randomize_sources(p * 977 + round, round == 1);
        next_frame_written();
        build_model(p);
        check_ram($sformatf("page %0d round %0d", p, round));
        checkPage = p;
        checkPixels = 1;
        wait_frame();
        checkPixels = 0;
      end
    end

    // literal checks of the formats (these also test the model)
    sources = '0;
    sources[SRC_AI_F0] = -5;
    sources[SRC_AI_F1] = 127;
    sources[SRC_AI_Y]  = -57344;
    sources[SRC_AI_H0] = 12345;          // does not fit in 3 digits
    sources[SRC_AI_ACTION] = 2;
    show_page(PAGE_WATCHDBG, "debug page");
    if (cells_text(57, 4, 4) != "-005")    fail($sformatf("SDEC -5 shown as '%s'", cells_text(57, 4, 4)));
    if (cells_text(57, 13, 4) != "+127")   fail($sformatf("SDEC 127 shown as '%s'", cells_text(57, 13, 4)));
    if (cells_text(57, 48, 7) != "-057344") fail($sformatf("SDEC -57344 shown as '%s'", cells_text(57, 48, 7)));
    if (cells_text(57, 40, 4) != "+999")   fail($sformatf("saturated SDEC shown as '%s'", cells_text(57, 40, 4)));
    if (cells_text(2, 10, 4) != "UP  ")    fail($sformatf("ACTION word shown as '%s'", cells_text(2, 10, 4)));
    if (dut.charRam[2 * 80 + 10][8:6] != 3'd5) fail("UP is not green");

    sources[SRC_MODE_CURSOR] = 1;
    show_page(PAGE_MODE, "mode menu");
    if (cells_text(9, 13, 1) != " " || cells_text(12, 13, 1) != ">" || cells_text(15, 13, 1) != " ")
      fail("mode cursor not on TRAIN AI");
    if (cells_text(12, 15, 8) != "TRAIN AI") fail("cursor field damaged the item text");
    if (dut.charRam[12 * 80 + 15][8:6] != 3'd1) fail("selected item is not gold");
    if (dut.charRam[9 * 80 + 15][8:6] != 3'd3)  fail("unselected item is not dim");

    // training screen formats
    sources[SRC_TR_BATCHES] = 3;
    sources[SRC_TR_RUNID]   = 32'h3F2C;
    sources[SRC_L5_STATE]   = LANE_DEAD;
    sources[SRC_TR_WORLD]   = 1;
    sources[SRC_TR_SIM]     = 6;
    sources[SRC_TR_MUT]     = 2;
    sources[SRC_TR_RESULT]  = 2;
    show_page(PAGE_TRAIN, "training screen");
    if (cells_text(41, 10, 8) != "###-----") fail($sformatf("BAR 3 shown as '%s'", cells_text(41, 10, 8)));
    if (cells_text(0, 19, 4) != "3F2C")     fail($sformatf("HEX shown as '%s'", cells_text(0, 19, 4)));
    if (cells_text(35, 24, 5) != "DEAD ")    fail($sformatf("lane 5 state shown as '%s'", cells_text(35, 24, 5)));
    if (dut.charRam[35 * 80 + 24][8:6] != 3'd4) fail("DEAD is not red");
    if (cells_text(1, 39, 2) != "B ")       fail($sformatf("world shown as '%s'", cells_text(1, 39, 2)));
    if (cells_text(0, 61, 5) != "X1024")    fail($sformatf("SIM shown as '%s'", cells_text(0, 61, 5)));
    if (cells_text(47, 26, 4) != "1/4 ")    fail($sformatf("mutation rate shown as '%s'", cells_text(47, 26, 4)));
    if (cells_text(51, 12, 8) != "SOLVED  ") fail($sformatf("result shown as '%s'", cells_text(51, 12, 8)));
    sources[SRC_TR_WORLD] = 9;
    next_frame_written();
    if (cells_text(1, 39, 2) != "T4")       fail($sformatf("test world shown as '%s'", cells_text(1, 39, 2)));
    // the lane windows and the chart area stay free of text and panels
    for (int c = 0; c < 80; c++)
      if (dut.charRam[10 * 80 + c] != 10'd0) begin
        fail("the lane window area is not empty in the character layer");
        break;
      end
    for (int c = 46; c < 80; c++)
      if (dut.charRam[45 * 80 + c] != 10'd0) begin
        fail("the chart area is not empty in the character layer");
        break;
      end

    sources[SRC_WORLD_SPEED] = 12;       // one digit: saturates at 9
    show_page(PAGE_SETUP, "setup banner");
    if (cells_text(29, 17, 1) != "9") fail("one-digit DEC did not saturate");
    sources[SRC_WORLD_SPEED] = 4;
    next_frame_written();
    if (cells_text(29, 17, 1) != "4") fail("DEC 4 not shown");

    // back to no page: hidden from the change on
    page = PAGE_NONE;
    repeat (4) @(posedge clk);
    expectHidden = 1;
    wait_frame();
    wait_frame();
    expectHidden = 0;

    $display("INFO: %0d pixels compared; longest field pass %0d clocks (blanking leaves about 25,800)",
             checkedPixels, worstPass);
    if (checkedPixels < 1000000) fail("too few pixels were compared");
    if (errors == 0) $display("PASS: tb_char_screen");
    else             $display("FAIL: tb_char_screen (%0d errors)", errors);
    $finish;
  end

endmodule
