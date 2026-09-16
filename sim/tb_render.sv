// Renders complete VGA frames of game_system into PPM images, exactly as the
// board would output them (including the drawing pipeline delay).
// Pixel colours are taken from the oVGA pins using the board wiring:
// oVGA[7:0] -> VGA_R, [15:8] -> VGA_G, [23:16] -> VGA_B.
//
//   +shots=<frame>,<frame>,...   save the listed frames (no key presses)
//   +scenario=tour               play through every screen with scripted keys
//   +difficulty=<0..2>           difficulty chosen in the tour (default 1)
//   +columns=<1..3>              coral columns chosen in the tour (default 3)
// Timers and the first coral position are shortened so a tour takes ~100 frames.
`timescale 1ns / 1ps

module tb_render;
  import game_state_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #15.873 clk = ~clk;

  logic [8:0]  keyCode = 9'h000;
  logic        keyMake = 1'b0;
  logic        keyBreak = 1'b0;
  logic [28:0] ovga;
  logic [6:0]  hex0, hex1, hex2, hex3, hex4, hex5;
  logic [9:0]  ledr;

  game_system dut (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .keyMake(keyMake), .keyBreak(keyBreak),
      .OVGA(ovga), .HEX0(hex0), .HEX1(hex1), .HEX2(hex2), .HEX3(hex3), .HEX4(hex4), .HEX5(hex5),
      .LEDR(ledr));

  defparam dut.gameLogic.READY_FRAMES     = 12;
  defparam dut.gameLogic.HIT_FRAMES       = 10;
  defparam dut.gameLogic.OVER_LOCK_FRAMES = 2;
  defparam dut.gameLogic.FIRST_X          = 250;

  localparam logic [8:0] KEY_UP = 9'h175, KEY_DOWN = 9'h172, KEY_ENTER = 9'h05A;

  int frameNo = 0;
  always @(posedge clk) if (dut.startOfFrame) frameNo++;

  logic [23:0] image [0:640*480-1];

  // Records the frame that starts at the next startOfFrame and writes it to fname.
  task automatic capture(input string fname);
    int fd;
    int x, y;
    for (int i = 0; i < 640 * 480; i++) image[i] = 24'hFF00FF;
    @(posedge clk iff dut.startOfFrame);
    @(negedge clk);
    while (!dut.startOfFrame) begin
      if (ovga[27]) begin
        x = int'(dut.vga.H_Cont) - 192;
        y = int'(dut.vga.V_Cont) - 40;
        if (x >= 0 && x < 640 && y >= 0 && y < 480)
          image[y * 640 + x] = {ovga[7:0], ovga[15:8], ovga[23:16]};
      end
      @(negedge clk);
    end
    fd = $fopen(fname, "w");
    $fwrite(fd, "P3\n640 480\n255\n");
    for (int i = 0; i < 640 * 480; i++)
      $fwrite(fd, "%0d %0d %0d\n", image[i][23:16], image[i][15:8], image[i][7:0]);
    $fclose(fd);
    $display("INFO: frame %0d (screen %0d, score %0d%0d%0d) -> %s", frameNo, dut.screen,
             dut.score[2], dut.score[1], dut.score[0], fname);
  endtask

  task automatic wait_frames(input int n);
    repeat (n) @(posedge clk iff dut.startOfFrame);
  endtask

  // The keyboard block updates keyCode with a one-clock make or break pulse.
  task automatic key_event(input logic [8:0] code, input bit isBreak);
    @(negedge clk);
    keyCode  = code;
    keyMake  = !isBreak;
    keyBreak = isBreak;
    @(negedge clk);
    keyMake  = 1'b0;
    keyBreak = 1'b0;
  endtask

  task automatic press(input logic [8:0] code);
    key_event(code, 0);
    repeat (1000) @(negedge clk);
    key_event(code, 1);
    wait_frames(1);
  endtask

  task automatic tour();
    int difficulty, columns;
    if (!$value$plusargs("difficulty=%d", difficulty)) difficulty = 1;
    if (!$value$plusargs("columns=%d", columns)) columns = 3;

    wait_frames(2);
    capture("tour_1_menu_difficulty.ppm");
    repeat (difficulty) press(KEY_DOWN);
    press(KEY_ENTER);
    repeat (columns - 1) press(KEY_DOWN);
    capture("tour_2_menu_obstacles.ppm");
    press(KEY_ENTER);
    wait_frames(3);
    capture("tour_3_get_ready.ppm");
    wait (dut.screen == ST_PLAY);
    // steer the maze upwards for a few frames, then let the bird crash
    key_event(KEY_UP, 0);
    wait_frames(12);
    key_event(KEY_UP, 1);
    wait_frames(8);
    capture("tour_4_play.ppm");
    // the crash may already have happened while steering
    wait (dut.screen == ST_HIT || dut.screen == ST_GAME_OVER);
    if (dut.screen == ST_HIT) capture("tour_5_hit_flash.ppm");
    wait (dut.screen == ST_GAME_OVER);
    wait_frames(3);
    capture("tour_6_game_over.ppm");
    press(KEY_DOWN);
    capture("tour_7_game_over_main_menu.ppm");
    press(KEY_ENTER);
    wait_frames(2);
    capture("tour_8_back_to_menu.ppm");
  endtask

  initial begin
    string shots;
    string scenario;
    int    target;
    int    pos;

    repeat (5) @(posedge clk);
    resetN = 1'b1;

    if ($value$plusargs("scenario=%s", scenario) && scenario == "tour") begin
      tour();
    end else begin
      if (!$value$plusargs("shots=%s", shots)) shots = "2";
      pos = 0;
      while (pos < shots.len()) begin
        target = 0;
        while (pos < shots.len() && shots[pos] >= "0" && shots[pos] <= "9") begin
          target = target * 10 + (shots[pos] - "0");
          pos++;
        end
        while (pos < shots.len() && (shots[pos] < "0" || shots[pos] > "9")) pos++;
        while (frameNo < target - 1) @(posedge clk);
        capture($sformatf("frame_%0d%0d%0d.ppm", target / 100, (target / 10) % 10, target % 10));
      end
    end
    $display("PASS: tb_render");
    $finish;
  end

endmodule
