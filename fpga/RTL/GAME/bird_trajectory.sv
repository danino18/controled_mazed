// Autonomous vertical motion of the bird. The bird never moves horizontally.
//
// EASY   - smooth sine bob from the supplied sintable (RTL/AUDIO/SinTable.sv):
//          fully predictable, 256 frames per bob, at most 4 px per frame.
// MEDIUM - every MEDIUM_INTERVAL frames a random bit picks up or down; the
//          speed eases towards +-MEDIUM_SPEED. Near the top or bottom the bird
//          always turns away from the edge.
// HARD   - pursuit of a random target height; both the target and the time
//          until the next target (6..37 frames) are random, so there is no
//          fixed rhythm. Speed and acceleration are limited and a small random
//          jitter is added every frame, so the motion stays smooth.
//
// All modes stay inside [BIRD_Y_MIN, BIRD_Y_MAX] and never exceed
// MAZE_STEP_MAX px per frame, so the player can always keep up.
// Positions and speeds are fixed point (1/64 px). Outputs change only on tick.

module bird_trajectory
  import game_params_pkg::*, game_state_pkg::*;
(
    input  logic               clk,
    input  logic               resetN,
    input  logic               tick,        // once per frame
    input  logic               run,         // advance the motion on tick
    input  logic               restart,     // return to the centre (one clock)
    input  logic [1:0]         mode,        // DIFF_EASY / DIFF_MEDIUM / DIFF_HARD
    input  logic [15:0]        rnd,         // random bits, sampled on tick
    output logic signed [10:0] birdY,       // top edge of the sprite, pixels
    output logic signed [11:0] birdVy,      // vertical speed, 1/64 px per frame
    output logic [7:0]         trajState    // EASY: phase, MEDIUM/HARD: frames to next decision
);

  localparam int FX      = 1 << FIXED_SHIFT;
  localparam int Y_MIN   = BIRD_Y_MIN * FX;
  localparam int Y_MAX   = BIRD_Y_MAX * FX;
  localparam int EDGE    = MEDIUM_EDGE_MARGIN * FX;

  // ---------------------------------------------------------------- sine source (EASY)
  logic [11:0] phase;                 // 1/16 table entries
  logic [15:0] sineQ;
  logic signed [7:0] sine;

  sintable #(.COUNT_SIZE(8)) sineTable (
      .clk   (clk),
      .resetN(resetN),
      .ADDR  (phase[11:4]),
      .volume(1'b1),                  // keeps the table at full scale
      .Q     (sineQ)
  );

  // At full volume Q = {s, table[7:0], {7{s}}}, so Q[14:7] is the signed sample (-128..127).
  assign sine = sineQ[14:7];

  // ---------------------------------------------------------------- state
  logic signed [17:0] posFx;
  logic signed [11:0] vyFx;
  logic [5:0]         decisionTimer;  // frames until the next random decision
  logic               goingDown;      // MEDIUM direction
  logic signed [17:0] targetFx;       // HARD target height

  // ---------------------------------------------------------------- next state (combinational)
  int easyPos;
  int desiredVy;
  int accel;
  int limit;
  int nextVy;
  int nextPos;
  int newTarget;
  logic decide;

  assign easyPos   = (BIRD_Y_CENTER + int'(sine)) * FX;
  assign decide    = (decisionTimer == 6'd0);
  // uniform-ish target in [Y_MIN, Y_MIN + 319] px: (r * 5) / 8 with r in 0..511
  assign newTarget = Y_MIN + (((int'(rnd[8:0]) << 2) + int'(rnd[8:0])) >>> 3) * FX;

  always_comb begin
    // desired vertical speed
    if (mode == DIFF_HARD) begin
      desiredVy = (int'(targetFx) - int'(posFx)) >>> 3;     // close 1/8 of the distance per frame
      limit     = HARD_MAX_SPEED;
      accel     = HARD_MAX_ACCEL;
    end else begin
      desiredVy = goingDown ? MEDIUM_SPEED : -MEDIUM_SPEED;
      limit     = MEDIUM_SPEED;
      accel     = MEDIUM_ACCEL;
    end
    if (desiredVy >  limit) desiredVy =  limit;
    if (desiredVy < -limit) desiredVy = -limit;

    // rate-limited change of speed, plus jitter in HARD
    nextVy = int'(vyFx);
    if (desiredVy > nextVy + accel)      nextVy = nextVy + accel;
    else if (desiredVy < nextVy - accel) nextVy = nextVy - accel;
    else                                 nextVy = desiredVy;
    if (mode == DIFF_HARD) nextVy = nextVy + (rnd[15] ? HARD_JITTER : -HARD_JITTER);
    if (nextVy >  limit) nextVy =  limit;
    if (nextVy < -limit) nextVy = -limit;

    // bounded position
    nextPos = int'(posFx) + nextVy;
    if (nextPos < Y_MIN) nextPos = Y_MIN;
    if (nextPos > Y_MAX) nextPos = Y_MAX;
  end

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      phase         <= '0;
      posFx         <= 18'(BIRD_Y_CENTER * FX);
      vyFx          <= '0;
      birdVy        <= '0;
      decisionTimer <= '0;
      goingDown     <= 1'b1;
      targetFx      <= 18'(BIRD_Y_CENTER * FX);
    end else if (restart) begin
      phase         <= '0;
      posFx         <= 18'(BIRD_Y_CENTER * FX);
      vyFx          <= '0;
      birdVy        <= '0;
      decisionTimer <= '0;
      goingDown     <= 1'b1;
      targetFx      <= 18'(BIRD_Y_CENTER * FX);
    end else if (tick && run) begin
      case (mode)
        DIFF_MEDIUM, DIFF_HARD: begin
          // random decisions
          if (decide) begin
            if (mode == DIFF_MEDIUM) begin
              decisionTimer <= 6'(MEDIUM_INTERVAL - 1);
              if (posFx < 18'(Y_MIN + EDGE))      goingDown <= 1'b1;
              else if (posFx > 18'(Y_MAX - EDGE)) goingDown <= 1'b0;
              else                                goingDown <= rnd[0];
            end else begin
              decisionTimer <= 6'(HARD_DWELL_MIN - 1) + 6'(rnd[14:10]);   // next decision in 6..37 frames
              targetFx      <= 18'(newTarget);
            end
          end else begin
            decisionTimer <= decisionTimer - 6'd1;
          end
          // motion; hitting a limit stops the bird there
          posFx  <= 18'(nextPos);
          vyFx   <= (nextPos == Y_MIN || nextPos == Y_MAX) ? 12'sd0 : 12'(nextVy);
          birdVy <= 12'(nextPos - int'(posFx));
        end
        default: begin   // EASY
          phase  <= phase + 12'(EASY_PHASE_STEP);
          posFx  <= 18'(easyPos);
          vyFx   <= 12'(easyPos - int'(posFx));
          birdVy <= 12'(easyPos - int'(posFx));
        end
      endcase
    end else if (tick) begin
      birdVy <= '0;
    end
  end

  assign birdY     = 11'(posFx >>> FIXED_SHIFT);
  assign trajState = (mode == DIFF_EASY) ? phase[11:4] : {2'b00, decisionTimer};

endmodule
