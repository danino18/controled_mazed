// Network inputs: feature_world + feature_lane against a reference model
// written from the design document (not from the RTL).
//
//   - the time-to-arrival table matches game_params_pkg for every speed level
//   - 50,000 random column layouts (1..3 columns, passed / on-screen /
//     off-screen columns, clamped openings, extreme bird and maze speeds)
//   - 30,000 frames of a real world_engine + lane_engine round per mode, with
//     random steering, so wraps, passes and clamps happen as in the game
//   - features never use a column that is off screen
`timescale 1ns / 1ps

module tb_features;
  import game_params_pkg::*, game_state_pkg::*, ml_pkg::*;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------- stimulus (random layouts or a real game)
  bit                           useGame = 1'b0;
  logic signed [10:0]           rBirdY;
  logic signed [11:0]           rBirdVy;
  logic [NUM_COLUMNS-1:0]       rActive;
  logic [NUM_COLUMNS-1:0][10:0] rColX;
  logic [NUM_COLUMNS-1:0][9:0]  rGapTop;
  logic signed [4:0]            rMazeVy;
  logic [2:0]                   speedLevel;

  // real game
  logic tickMove = 1'b0, tickCheck = 1'b0;
  logic seedLoad = 1'b0, restart = 1'b0;
  logic [15:0] seed = 16'h0001;
  logic [1:0]  mode = DIFF_EASY, columns = 2'd1;
  logic up = 1'b0, down = 1'b0;
  logic signed [10:0]           gBirdY;
  logic signed [11:0]           gBirdVy;
  logic [7:0]                   gTraj;
  logic [NUM_COLUMNS-1:0]       gActive;
  logic [NUM_COLUMNS-1:0][10:0] gColX;
  logic [NUM_COLUMNS-1:0][8:0]  gGapBase;
  logic                         gPass;
  logic signed [9:0]            gOffset;
  logic signed [4:0]            gMazeVy;
  logic [NUM_COLUMNS-1:0][9:0]  gGapTop, gGapBottom;
  logic                         gCollision;
  logic [NUM_COLUMNS-1:0]       gHit;

  world_engine world (
      .clk(clk), .resetN(resetN), .tickMove(tickMove), .tickCheck(tickCheck),
      .seedLoad(seedLoad), .seed(seed), .restart(restart), .birdReset(1'b0),
      .birdRun(1'b1), .worldRun(1'b1), .birdMode(mode), .columnCount(columns),
      .worldStep(12'(WORLD_STEP_BASE) + 12'(WORLD_STEP_INCREMENT) * 12'(speedLevel)),
      .birdY(gBirdY), .birdVy(gBirdVy), .birdTrajState(gTraj), .colActive(gActive),
      .colX(gColX), .gapBase(gGapBase), .passPulse(gPass));

  lane_engine lane (
      .clk(clk), .resetN(resetN), .tickMove(tickMove), .tickCheck(tickCheck),
      .steerRun(1'b1), .restart(restart), .moveUp(up), .moveDown(down),
      .birdY(gBirdY), .colActive(gActive), .colX(gColX), .gapBase(gGapBase),
      .mazeOffset(gOffset), .mazeVy(gMazeVy), .gapTop(gGapTop), .gapBottom(gGapBottom),
      .collision(gCollision), .hitColumn(gHit));

  logic signed [10:0]           birdY;
  logic signed [11:0]           birdVy;
  logic [NUM_COLUMNS-1:0]       active;
  logic [NUM_COLUMNS-1:0][10:0] colX;
  logic [NUM_COLUMNS-1:0][9:0]  gapTop;
  logic signed [4:0]            mazeVy;

  assign birdY  = useGame ? gBirdY  : rBirdY;
  assign birdVy = useGame ? gBirdVy : rBirdVy;
  assign active = useGame ? gActive : rActive;
  assign colX   = useGame ? gColX   : rColX;
  assign gapTop = useGame ? gGapTop : rGapTop;
  assign mazeVy = useGame ? gMazeVy : rMazeVy;

  // ---------------------------------------------------------------- DUT
  logic sampleW = 1'b0, sampleL = 1'b0;
  logic [1:0] next1, next2;
  logic vis1, use2;
  logic [6:0] tau;
  logic signed [10:0] birdC;
  logic signed [11:0] birdVyW;
  logic [NN_INPUTS-1:0][7:0] feat;
  logic aligned;
  logic signed [10:0] eNext;

  feature_world fw (
      .clk(clk), .resetN(resetN), .sample(sampleW), .birdY(birdY), .birdVy(birdVy),
      .colActive(active), .colX(colX), .speedLevel(speedLevel),
      .next1(next1), .next2(next2), .vis1(vis1), .use2(use2), .tau(tau),
      .birdC(birdC), .birdVyOut(birdVyW));

  feature_lane fl (
      .clk(clk), .resetN(resetN), .sample(sampleL), .next1(next1), .next2(next2),
      .vis1(vis1), .use2(use2), .tau(tau), .birdC(birdC), .birdVy(birdVyW),
      .gapTop(gapTop), .mazeVy(mazeVy), .feat(feat), .aligned(aligned), .eNext(eNext));

  int errors = 0;
  int checks = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 20) $display("FAIL: %s", msg);
  endtask

  // ---------------------------------------------------------------- reference model
  function automatic int sat(input int v, input int lo, input int hi);
    return v < lo ? lo : v > hi ? hi : v;
  endfunction

  function automatic int floor_div(input int a, input int b);   // b > 0
    return a >= 0 ? a / b : -((-a + b - 1) / b);
  endfunction

  int expF [NN_INPUTS];
  bit expAligned;
  int expN1, expN2;
  bit expVis1, expUse2;

  task automatic reference();
    int x [NUM_COLUMNS];
    int n1, n2, e1, e2, vrel, dx, t, centre1, centre2, bc, ws;
    for (int i = 0; i < NUM_COLUMNS; i++) x[i] = int'($signed(colX[i]));
    // next column: still to be passed (core right edge not left of the hitbox), smallest x
    n1 = -1;
    for (int i = 0; i < NUM_COLUMNS; i++)
      if (active[i] && x[i] + CORAL_W - CORAL_CORE_INSET > BIRD_X + BIRD_HB_X0)
        if (n1 < 0 || x[i] < x[n1]) n1 = i;
    // the one after it: smallest x beyond next
    n2 = -1;
    if (n1 >= 0)
      for (int i = 0; i < NUM_COLUMNS; i++)
        if (active[i] && x[i] > x[n1] && (n2 < 0 || x[i] < x[n2])) n2 = i;
    expVis1 = (n1 >= 0) && x[n1] < SCREEN_W;
    expUse2 = expVis1 && (n2 >= 0) && x[n2] < SCREEN_W;
    expN1 = n1 < 0 ? 0 : n1;
    expN2 = n2 < 0 ? expN1 : n2;
    bc = int'(birdY) + (BIRD_HB_Y0 + BIRD_HB_Y1) / 2;
    centre1 = int'(gapTop[expN1]) + GAP_H / 2;
    centre2 = int'(gapTop[expN2]) + GAP_H / 2;
    e1 = expVis1 ? centre1 - bc : 0;
    e2 = expUse2 ? centre2 - bc : e1;
    vrel = int'(mazeVy) * 64 - int'(birdVy);
    // frames until the core reaches the hitbox: dx pixels at worldStep/64 px per frame
    ws = WORLD_STEP_BASE + WORLD_STEP_INCREMENT * int'(speedLevel);
    dx = x[expN1] + CORAL_CORE_INSET - (BIRD_X + BIRD_HB_X1);
    if (!expVis1)     t = 127;
    else if (dx <= 0) t = 0;
    else              t = sat((dx * ((16384 + ws / 2) / ws)) / 256, 0, 127);
    expF[0] = sat(floor_div(e1, 2), -128, 127);
    expF[1] = sat(floor_div(e2, 2), -128, 127);
    expF[2] = sat(floor_div(vrel, 4), -128, 127);
    expF[3] = t;
    expAligned = expVis1 && e1 >= -ALIGN_TOL && e1 <= ALIGN_TOL;
  endtask

  task automatic sample_and_check(input string what);
    @(negedge clk);          // let the stimulus settle
    reference();
    sampleW = 1'b1;
    @(negedge clk);
    sampleW = 1'b0;
    sampleL = 1'b1;
    @(negedge clk);
    sampleL = 1'b0;
    checks++;
    if (vis1 != expVis1 || use2 != expUse2 || (expVis1 && next1 != expN1) || (expUse2 && next2 != expN2))
      fail($sformatf("%s: next %0d/%0d vis %0d use %0d, expected %0d/%0d %0d %0d (x %0d %0d %0d, active %b)",
                     what, next1, next2, vis1, use2, expN1, expN2, expVis1, expUse2,
                     $signed(colX[0]), $signed(colX[1]), $signed(colX[2]), active));
    for (int i = 0; i < NN_INPUTS; i++)
      if (int'($signed(feat[i])) != expF[i])
        fail($sformatf("%s: F%0d = %0d, expected %0d", what, i, $signed(feat[i]), expF[i]));
    if (aligned != expAligned) fail($sformatf("%s: aligned %0d, expected %0d", what, aligned, expAligned));
  endtask

  // ---------------------------------------------------------------- real game frames
  task automatic game_frame();
    @(negedge clk);
    tickMove = 1'b1;
    @(negedge clk);
    tickMove = 1'b0;
    tickCheck = 1'b1;
    @(negedge clk);
    tickCheck = 1'b0;
  endtask

  initial begin
    int seedR;
    int vis2seen, offscreenSeen, overlapSeen, farSeen;
    seedR = 7;
    vis2seen = 0; offscreenSeen = 0; overlapSeen = 0; farSeen = 0;

    // ---- the time-to-arrival table
    for (int l = 0; l < 8; l++) begin
      int ws, expected;
      logic [8:0] table_value;
      ws = WORLD_STEP_BASE + WORLD_STEP_INCREMENT * l;
      expected = (256 * (1 << FIXED_SHIFT) + ws / 2) / ws;
      case (l)
        0: table_value = TAU_RECIP_0;  1: table_value = TAU_RECIP_1;
        2: table_value = TAU_RECIP_2;  3: table_value = TAU_RECIP_3;
        4: table_value = TAU_RECIP_4;  5: table_value = TAU_RECIP_5;
        6: table_value = TAU_RECIP_6;  default: table_value = TAU_RECIP_7;
      endcase
      if (table_value != expected) fail($sformatf("TAU_RECIP_%0d = %0d, expected %0d", l, table_value, expected));
    end
    if (NOT_PASSED_X != 94) fail($sformatf("NOT_PASSED_X = %0d, expected 94", NOT_PASSED_X));

    repeat (3) @(negedge clk);
    resetN = 1'b1;

    // ---- random layouts
    for (int n = 0; n < 50000; n++) begin
      int count;
      count = 1 + $urandom(seedR) % 3; seedR++;
      rActive = NUM_COLUMNS'((1 << count) - 1);
      for (int i = 0; i < NUM_COLUMNS; i++) begin
        int x;
        // mostly realistic positions, sometimes anywhere in range
        x = int'($urandom(seedR) % 1090) - 64; seedR++;
        if (n % 5 == 0) x = 60 + int'($urandom(seedR) % 80); seedR++;   // around the pass line
        rColX[i]   = 11'(x);
        rGapTop[i] = 10'(16 + $urandom(seedR) % 321); seedR++;
      end
      if (n % 7 == 0) rColX[1] = rColX[0];           // equal x (not in the game, but defined)
      rBirdY     = 11'(64 + $urandom(seedR) % 321); seedR++;
      rBirdVy    = 12'(int'($urandom(seedR) % 601) - 300); seedR++;
      rMazeVy    = 5'(int'($urandom(seedR) % 9) - 4); seedR++;
      speedLevel = 3'($urandom(seedR)); seedR++;
      sample_and_check($sformatf("layout %0d", n));
      if (expUse2) vis2seen++;
      if (!expVis1) offscreenSeen++;
      if (expVis1 && expF[3] == 0) overlapSeen++;
      if (expVis1 && expF[3] == 127) farSeen++;
    end
    $display("INFO: random layouts: %0d with a second column, %0d without a visible next column, %0d overlapping, %0d far",
             vis2seen, offscreenSeen, overlapSeen, farSeen);
    if (vis2seen == 0 || offscreenSeen == 0 || overlapSeen == 0 || farSeen == 0) fail("random layouts missed a case");

    // ---- real rounds
    useGame = 1'b1;
    for (int m = 0; m < 9; m++) begin
      int steer;
      mode       = 2'(m / 3);
      columns    = 2'(m % 3 + 1);
      speedLevel = 3'((m * 3) % 8);
      seed       = 16'(16'h1D2B + m * 16'h0101);
      @(negedge clk); seedLoad = 1'b1;
      @(negedge clk); seedLoad = 1'b0; restart = 1'b1;
      @(negedge clk); restart = 1'b0;
      steer = 0;
      for (int f = 0; f < 3300; f++) begin
        // random steering held for a few frames at a time
        if (f % 6 == 0) begin
          steer = $urandom(seedR) % 3; seedR++;
        end
        up   = (steer == 1);
        down = (steer == 2);
        game_frame();
        sample_and_check($sformatf("mode %0d frame %0d", m, f));
      end
    end
    $display("INFO: %0d feature samples checked", checks);

    if (errors == 0) $display("PASS: tb_features");
    else             $display("FAIL: tb_features (%0d errors)", errors);
    $finish;
  end

endmodule
