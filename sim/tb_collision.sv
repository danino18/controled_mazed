// Checks collision_detect: hand-derived boundary cases, then random layouts
// against a reference model written from the specification.
`timescale 1ns / 1ps

module tb_collision;
  import game_params_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic                         tickCheck = 1'b0;
  logic signed [10:0]           birdY;
  logic [NUM_COLUMNS-1:0]       active;
  logic [NUM_COLUMNS-1:0][10:0] colX;
  logic [NUM_COLUMNS-1:0][9:0]  gapTop, gapBottom;
  logic                         collision;
  logic [NUM_COLUMNS-1:0]       hitColumn;

  collision_detect dut (
      .clk(clk), .resetN(resetN), .tickCheck(tickCheck), .birdY(birdY),
      .active(active), .colX(colX), .gapTop(gapTop), .gapBottom(gapBottom),
      .collision(collision), .hitColumn(hitColumn));

  int errors = 0;

  // Bird hitbox: x 153..169, y birdY+10 .. birdY+24 (inclusive).
  // Coral core: x colX+4 .. colX+59; coral rows are y < gapTop-8 and y >= gapBottom+8.
  function automatic bit model_hit(int by, int cx, int gt, int gb);
    bit xo, yo;
    xo = (169 >= cx + 4) && (153 <= cx + 59);
    yo = (by + 10 < gt - 8) || (by + 24 >= gb + 8);
    return xo && yo;
  endfunction

  task automatic check(input int by, input int cx, input int gt, input bit act,
                       input bit expected, input string name);
    birdY = 11'(by);
    active = '0;
    colX = '0;
    gapTop = '0;
    gapBottom = '0;
    active[1] = act;
    colX[1] = 11'(cx);
    gapTop[1] = 10'(gt);
    gapBottom[1] = 10'(gt + GAP_H);
    colX[0] = 11'(600);            // an unrelated active column far away
    active[0] = 1'b1;
    gapTop[0] = 10'd100;
    gapBottom[0] = 10'd228;
    @(negedge clk);
    tickCheck = 1'b1;
    @(negedge clk);
    tickCheck = 1'b0;
    if (collision !== expected || hitColumn[1] !== expected || hitColumn[0] !== 1'b0) begin
      errors++;
      $display("FAIL: %s: collision=%b hit=%b expected %b", name, collision, hitColumn, expected);
    end
  endtask

  initial begin
    repeat (2) @(negedge clk);
    resetN = 1'b1;

    // opening rows 200..327, safe rows 192..335
    check(190, 120, 200, 1, 0, "bird inside the opening");
    check(181, 120, 200, 1, 1, "hitbox one row into the upper coral");
    check(182, 120, 200, 1, 0, "hitbox touches only the forgiving upper tips");
    check(311, 120, 200, 1, 0, "hitbox touches only the forgiving lower tips");
    check(312, 120, 200, 1, 1, "hitbox one row into the lower coral");
    check(100, 170, 200, 1, 0, "bird left of the core (overlaps only the knobbly side)");
    check(100, 165, 200, 1, 1, "core's left edge reaches the hitbox");
    check(100, 94,  200, 1, 1, "core's right edge still on the hitbox");
    check(100, 93,  200, 1, 0, "core just passed the hitbox");
    check(100, 120, 200, 0, 0, "inactive column never collides");
    check(100, -64, 200, 1, 0, "column off screen on the left");

    // multi-column layouts: each column can cause the crash, inactive ones never do
    for (int target = 0; target < NUM_COLUMNS; target++) begin
      for (int count = 1; count <= NUM_COLUMNS; count++) begin
        birdY = 11'd100;                                   // hitbox rows 110..124
        for (int i = 0; i < NUM_COLUMNS; i++) begin
          active[i]    = (i < count);
          colX[i]      = 11'(i == target ? 120 : 400 + 100 * i);   // only the target overlaps the bird
          gapTop[i]    = 10'd200;                          // bird above every opening -> crash on overlap
          gapBottom[i] = 10'd328;
        end
        @(negedge clk);
        tickCheck = 1'b1;
        @(negedge clk);
        tickCheck = 1'b0;
        if (collision !== (target < count) || hitColumn !== ((target < count) ? 3'(1 << target) : 3'b000)) begin
          errors++;
          $display("FAIL: %0d active columns, column %0d over the bird: collision=%b hit=%b",
                   count, target, collision, hitColumn);
        end
      end
    end
    // the bird inside the opening of the overlapping column is safe even if others would hit elsewhere
    birdY = 11'd220;
    for (int i = 0; i < NUM_COLUMNS; i++) begin
      active[i]    = 1'b1;
      colX[i]      = 11'(120 + 240 * i);
      gapTop[i]    = 10'(i == 0 ? 200 : 16);
      gapBottom[i] = 10'(i == 0 ? 328 : 144);
    end
    @(negedge clk);
    tickCheck = 1'b1;
    @(negedge clk);
    tickCheck = 1'b0;
    if (collision !== 1'b0) begin
      errors++;
      $display("FAIL: far columns caused a collision");
    end

    // random layouts
    for (int n = 0; n < 20000; n++) begin
      int by, cx, gt;
      bit act, exp_hit;
      by  = $urandom_range(BIRD_Y_MAX, BIRD_Y_MIN);
      cx  = $urandom_range(700, 0) - 64;
      gt  = $urandom_range(GAP_CENTER_MAX, GAP_CENTER_MIN) - GAP_H / 2;
      act = $urandom_range(1, 0);
      exp_hit = act && model_hit(by, cx, gt, gt + GAP_H);
      check(by, cx, gt, act, exp_hit, $sformatf("random y=%0d x=%0d top=%0d", by, cx, gt));
      if (errors > 10) break;
    end

    if (errors == 0) $display("PASS: tb_collision");
    else             $display("FAIL: tb_collision (%0d errors)", errors);
    $finish;
  end

endmodule
