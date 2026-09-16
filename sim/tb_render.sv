// Renders complete VGA frames of game_system into PPM images, exactly as the
// board would output them (including the drawing pipeline delay).
// Pixel colours are taken from the oVGA pins using the board wiring:
// oVGA[7:0] -> VGA_R, [15:8] -> VGA_G, [23:16] -> VGA_B.
//
// Run with +shots=<frame>,<frame>,... to choose which frames to save.
`timescale 1ns / 1ps

module tb_render;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #15.873 clk = ~clk;

  logic [28:0] ovga;
  logic [6:0]  hex0, hex1, hex2, hex3, hex4, hex5;
  logic [9:0]  ledr;

  logic [8:0] keyCode = 9'h000;
  logic       keyMake = 1'b0;
  logic       keyBreak = 1'b0;

  game_system dut (
      .clk(clk), .resetN(resetN), .keyCode(keyCode), .keyMake(keyMake), .keyBreak(keyBreak), .OVGA(ovga),
      .HEX0(hex0), .HEX1(hex1), .HEX2(hex2), .HEX3(hex3), .HEX4(hex4), .HEX5(hex5),
      .LEDR(ledr));

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
    $display("INFO: frame %0d -> %s", frameNo, fname);
  endtask

  initial begin
    string shots;
    int    target;
    int    pos;
    if (!$value$plusargs("shots=%s", shots)) shots = "2";

    repeat (5) @(posedge clk);
    resetN = 1'b1;

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
    $display("PASS: tb_render");
    $finish;
  end

endmodule
