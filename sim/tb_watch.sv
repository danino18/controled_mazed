// WATCH AI, headless: game_logic steered by ai_player with the hand-set demo
// network (RTL/MIF/nn_demo.mif), in all nine difficulty/column modes at three
// world speeds. One frame every 64 clocks, enough for the 42-clock evaluation.
//
// Checks:
//   - the AI never moves the maze during GET READY (every round starts centred)
//   - on every move in PLAY the maze moves exactly as the AI's action says
//     (UP lowers the offset, DOWN raises it, HOLD keeps it), with the same
//     1..4 px/frame ramp a held key gives
//   - each AI action comes from the network evaluated on this frame's state
//     (checked against an integer model of the features and the network)
//   - the score equals the columns passed
//   - the demo network actually plays: it scores in every mode
`timescale 1ns / 1ps

module tb_watch;
  import game_params_pkg::*, game_state_pkg::*, ml_pkg::*;

  localparam int CLOCKS_PER_FRAME = 64;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  int   phase = 0;
  logic tickMove, tickCheck, tickState;
  always @(posedge clk) phase <= (phase + 1) % CLOCKS_PER_FRAME;
  assign tickMove  = resetN && (phase == 0);
  assign tickCheck = resetN && (phase == 1);
  assign tickState = resetN && (phase == 2);

  logic upPulse = 1'b0, downPulse = 1'b0, enterPulse = 1'b0;
  logic speedLoad = 1'b0;
  logic abort = 1'b0;
  logic [2:0] speedLoadLevel = 3'd0;

  logic [2:0]                   screen;
  logic [1:0]                   difficulty, columnCount, menuCursor;
  logic [7:0]                   stateFrames;
  logic signed [10:0]           birdY;
  logic signed [11:0]           birdVy;
  logic [7:0]                   birdTrajState;
  logic signed [9:0]            mazeOffset;
  logic signed [4:0]            mazeVy;
  logic [NUM_COLUMNS-1:0]       colActive;
  logic [NUM_COLUMNS-1:0][10:0] colX;
  logic [NUM_COLUMNS-1:0][8:0]  gapBase;
  logic [NUM_COLUMNS-1:0][9:0]  gapTop, gapBottom;
  logic                         collision;
  logic [NUM_COLUMNS-1:0]       hitColumn;
  logic [2:0][3:0]              score, best;
  logic                         newBest;
  logic [2:0]                   speedLevel;
  logic                         scoreEvent, failEvent;
  logic                         aiUp, aiDown, aiValid;
  logic [NN_INPUTS-1:0][7:0]    feat;
  logic signed [ACC_W-1:0]      y;
  logic signed [7:0]            h0;

  game_logic #(.READY_FRAMES(20), .HIT_FRAMES(5), .OVER_LOCK_FRAMES(2)) game (
      .clk(clk), .resetN(resetN), .tickMove(tickMove), .tickCheck(tickCheck), .tickState(tickState),
      .upHeld(1'b0), .downHeld(1'b0), .upPulse(upPulse), .downPulse(downPulse),
      .enterPulse(enterPulse), .speedUpHeld(1'b0), .speedDownHeld(1'b0), .entropyPulse(enterPulse),
      .aiMode(1'b1), .aiUp(aiUp), .aiDown(aiDown), .aiValid(aiValid),
      .trainMode(1'b0), .autoStart(1'b0), .autoDifficulty(2'd0), .autoColumns(2'd1), .abort(abort),
      .speedLoad(speedLoad), .speedLoadLevel(speedLoadLevel), .trainStart(),
      .screen(screen), .difficulty(difficulty), .columnCount(columnCount), .menuCursor(menuCursor),
      .stateFrames(stateFrames), .birdY(birdY), .birdVy(birdVy), .birdTrajState(birdTrajState),
      .mazeOffset(mazeOffset), .mazeVy(mazeVy), .colActive(colActive), .colX(colX), .gapBase(gapBase),
      .gapTop(gapTop), .gapBottom(gapBottom), .collision(collision), .hitColumn(hitColumn),
      .score(score), .best(best), .newBest(newBest), .speedLevel(speedLevel),
      .scoreEvent(scoreEvent), .failEvent(failEvent));

  ai_player #(.NET_FILE("RTL/MIF/nn_demo.mif")) ai (
      .clk(clk), .resetN(resetN), .enable(1'b1), .tickState(tickState),
      .birdY(birdY), .birdVy(birdVy), .colActive(colActive), .colX(colX), .gapTop(gapTop),
      .mazeVy(mazeVy), .speedLevel(speedLevel),
      .netWe(1'b0), .netWa('0), .netWd('0),
      .aiUp(aiUp), .aiDown(aiDown), .aiValid(aiValid), .feat(feat), .y(y), .h0(h0));

  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors < 20) $display("FAIL: %s", msg);
  endtask

  task automatic frames(input int n);
    repeat (n) @(posedge clk iff phase == CLOCKS_PER_FRAME - 1);
  endtask

  task automatic pulse(ref logic sig);
    @(negedge clk);
    sig = 1'b1;
    @(negedge clk);
    sig = 1'b0;
    frames(1);
  endtask

  function automatic int dec(input logic [2:0][3:0] d);
    return d[2] * 100 + d[1] * 10 + d[0];
  endfunction

  // ---------------------------------------------------------------- reference: features + demo network
  logic [7:0] genes [NN_GENES];
  initial $readmemh("RTL/MIF/nn_demo.hex", genes);

  function automatic int sat(input int v, input int lo, input int hi);
    return v < lo ? lo : v > hi ? hi : v;
  endfunction

  function automatic int fdiv(input int a, input int b);
    return a >= 0 ? a / b : -((-a + b - 1) / b);
  endfunction

  function automatic int ref_action();
    int x [NUM_COLUMNS];
    int n1, n2, f [4], bc, e1, e2, ws, dx, a, h [NN_HIDDEN], outSum;
    bit v1, v2;
    for (int i = 0; i < NUM_COLUMNS; i++) x[i] = int'($signed(colX[i]));
    n1 = -1;
    for (int i = 0; i < NUM_COLUMNS; i++)
      if (colActive[i] && x[i] >= 94 && (n1 < 0 || x[i] < x[n1])) n1 = i;
    n2 = -1;
    if (n1 >= 0)
      for (int i = 0; i < NUM_COLUMNS; i++)
        if (colActive[i] && x[i] > x[n1] && (n2 < 0 || x[i] < x[n2])) n2 = i;
    v1 = n1 >= 0 && x[n1] < 640;
    v2 = v1 && n2 >= 0 && x[n2] < 640;
    bc = int'(birdY) + 17;
    e1 = v1 ? int'(gapTop[n1]) + 64 - bc : 0;
    e2 = v2 ? int'(gapTop[n2]) + 64 - bc : e1;
    ws = 64 + 32 * int'(speedLevel);
    dx = v1 ? x[n1] + 4 - 169 : 0;
    f[0] = sat(fdiv(e1, 2), -128, 127);
    f[1] = sat(fdiv(e2, 2), -128, 127);
    f[2] = sat(fdiv(int'(mazeVy) * 64 - int'(birdVy), 4), -128, 127);
    f[3] = !v1 ? 127 : dx <= 0 ? 0 : sat((dx * ((16384 + ws / 2) / ws)) / 256, 0, 127);
    for (int j = 0; j < NN_HIDDEN; j++) begin
      a = int'($signed(genes[5 * j])) * 64;
      for (int i = 0; i < 4; i++) a += f[i] * int'($signed(genes[5 * j + 1 + i]));
      h[j] = sat(fdiv(a, 32), -64, 64);
    end
    outSum = int'($signed(genes[30])) * 64;
    for (int j = 0; j < NN_HIDDEN; j++) outSum += h[j] * int'($signed(genes[31 + j]));
    return outSum > 512 ? 2 : outSum < -512 ? 1 : 0;
  endfunction

  // Reference action for the state after this frame's update, checked when the
  // DUT's evaluation is finished (just before the next move).
  int expectedAct = 0;
  int checkedActions = 0;
  always @(posedge clk) begin
    if (resetN && phase == 3) expectedAct = ref_action();
    if (resetN && phase == CLOCKS_PER_FRAME - 1 && aiValid && (screen == ST_PLAY || screen == ST_READY)) begin
      checkedActions++;
      if ({aiUp, aiDown} != 2'(expectedAct))
        fail($sformatf("action %b, reference %0d (e_next feature %0d)", {aiUp, aiDown}, expectedAct, $signed(feat[0])));
    end
  end

  // The maze follows the action on every move in PLAY and never moves in READY.
  int prevOffset = 0;
  logic [1:0] actAtMove;
  logic [2:0] screenAtMove;
  int moves [3];
  always @(posedge clk) begin
    if (resetN && tickMove) begin
      actAtMove    <= {aiUp && aiValid, aiDown && aiValid};
      screenAtMove <= screen;
      prevOffset   <= int'(mazeOffset);
    end
    if (resetN && tickCheck) begin
      int moved;
      moved = int'(mazeOffset) - prevOffset;
      if (screenAtMove == ST_READY && moved != 0) fail($sformatf("maze moved %0d px during GET READY", moved));
      if (screenAtMove == ST_PLAY) begin
        case (actAtMove)
          ACT_UP:   begin if (moved > 0 || moved < -MAZE_STEP_MAX) fail($sformatf("UP moved the maze %0d", moved)); moves[2]++; end
          ACT_DOWN: begin if (moved < 0 || moved >  MAZE_STEP_MAX) fail($sformatf("DOWN moved the maze %0d", moved)); moves[1]++; end
          default:  begin if (moved != 0) fail($sformatf("HOLD moved the maze %0d", moved)); moves[0]++; end
        endcase
      end
    end
  end

  // columns passed, counted independently
  int passes = 0;
  int prevX [NUM_COLUMNS];
  always @(posedge clk) begin
    if (tickCheck && screen == ST_PLAY)
      for (int i = 0; i < NUM_COLUMNS; i++)
        if (colActive[i] && prevX[i] + 60 > 153 && int'($signed(colX[i])) + 60 <= 153) passes++;
    if (tickCheck) for (int i = 0; i < NUM_COLUMNS; i++) prevX[i] = int'($signed(colX[i]));
  end

  task automatic select(input int diff, input int cols);
    while (menuCursor > diff) pulse(upPulse);
    while (menuCursor < diff) pulse(downPulse);
    pulse(enterPulse);
    while (menuCursor > cols - 1) pulse(upPulse);
    while (menuCursor < cols - 1) pulse(downPulse);
    pulse(enterPulse);
  endtask

  initial begin
    int speeds [3] = '{1, 3, 6};
    int totalScore, lowest;
    string report;
    repeat (3) @(negedge clk);
    resetN = 1'b1;
    frames(3);
    totalScore = 0;
    lowest = 1000;

    for (int s = 0; s < 3; s++) begin
      @(negedge clk);
      speedLoad = 1'b1;
      speedLoadLevel = 3'(speeds[s]);
      @(negedge clk);
      speedLoad = 1'b0;
      report = $sformatf("INFO: speed level %0d:", speeds[s]);
      for (int m = 0; m < 9; m++) begin
        int survived;
        select(m / 3, m % 3 + 1);
        wait (screen == ST_PLAY);
        passes = 0;
        survived = 0;
        while (screen == ST_PLAY && survived < 2500) begin
          frames(1);
          survived++;
        end
        if (dec(score) != passes) fail($sformatf("score %0d but %0d columns passed", dec(score), passes));
        if (dec(score) == 0) fail($sformatf("mode %0d/%0d speed %0d: the demo network never scored", m / 3, m % 3 + 1, speeds[s]));
        totalScore += dec(score);
        if (dec(score) < lowest) lowest = dec(score);
        report = {report, $sformatf(" %s%0d:%0d%s", m / 3 == 0 ? "E" : m / 3 == 1 ? "M" : "H", m % 3 + 1,
                                    survived, survived < 2500 ? "x" : "")};
        // end the round: after a crash choose MAIN MENU, otherwise abort
        if (screen == ST_PLAY) begin
          pulse(abort);
        end else begin
          wait (screen == ST_GAME_OVER);
          frames(3);
          pulse(downPulse);
          pulse(enterPulse);         // MAIN MENU
        end
        if (screen != ST_MENU_DIFF) fail("did not return to the first menu");
      end
      $display("%s", report);
    end
    $display("INFO: frames survived per mode (x = crashed); %0d actions checked; moves: %0d hold, %0d down, %0d up; lowest score %0d",
             checkedActions, moves[0], moves[1], moves[2], lowest);
    if (moves[1] == 0 || moves[2] == 0 || moves[0] == 0) fail("not every action was used");

    if (errors == 0) $display("PASS: tb_watch");
    else             $display("FAIL: tb_watch (%0d errors)", errors);
    $finish;
  end

endmodule
