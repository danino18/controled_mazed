// Plays the score and failure sound effects through the supplied audio chain
// (melody_player_1 -> ToneDecoder -> prescaler -> addr_counter -> sintable),
// with a small arbiter in front since only one melody can play at a time.
//
// scoreTrigger and failTrigger are one-clock pulses tied directly to the same
// events that award the point (obstacle_manager's scorePulse) and end the
// round (game_fsm's roundOver) -- there is no separate scoring/sound path, so
// a sound cannot fire without its matching game event or vice versa.
//
// Failure can only happen once before a new round starts (game_fsm freezes
// gameplay after a collision), so one pending bit is enough for it. Score
// events can in principle queue up faster than the ~0.2-0.3 s jingles play,
// so pendingScore is a small saturating counter: every trigger is eventually
// played, in the order fail (higher priority) then score.
//
// melodySelect must be stable for two clocks before startMelody pulses, so
// the supplied melody_player_1's registered-address songs.mif read has
// settled to the right melody before its state machine reads the first
// note's duration (S_SET is exactly that one settle cycle).

module sound_engine (
    input  logic         clk,
    input  logic         resetN,
    input  logic         scoreTrigger,
    input  logic         failTrigger,
    input  logic         mute,          // SW0: gates only the final PCM sample
    output logic [15:0]  audioSample,   // signed PCM, ready for the codec's DAC input
    output logic         playingScore,  // debug/test: a score jingle is currently playing
    output logic         playingFail    // debug/test: the failure tone is currently playing
);

  localparam logic [3:0] SCORE_MELODY = 4'd0;
  localparam logic [3:0] FAIL_MELODY  = 4'd1;
  localparam int         PENDING_SCORE_MAX = 7;

  enum logic [1:0] {S_IDLE, S_SET, S_FIRE, S_WAIT} state;

  logic [3:0] melodySelectReg;
  logic [2:0] pendingScore;
  logic       pendingFail;

  logic       startMelody;
  logic [3:0] tone;
  logic [2:0] octave;
  logic       enableSoundOut;
  logic       melodyEnded;

  assign startMelody = (state == S_FIRE);

  // A new trigger and S_FIRE consuming the head of that same queue can land on
  // the same clock (three score events in quick succession is enough to hit
  // this). Two separate "pendingX <= pendingX +/- 1" statements would race --
  // whichever is later in program order silently wins and the other's count
  // is lost -- so both events are folded into one next-value computation per
  // counter instead, and "arrive and consume in the same cycle" nets to zero.
  logic scoreConsume, failConsume;
  logic scoreArrive, failArrive;
  logic [2:0] pendingScoreNext;

  assign scoreConsume = (state == S_FIRE) && (melodySelectReg == SCORE_MELODY);
  assign failConsume  = (state == S_FIRE) && (melodySelectReg == FAIL_MELODY);
  // A slot is free either because one is already free, or because this same
  // cycle's S_FIRE is about to consume one (see pendingScoreNext below).
  assign scoreArrive  = scoreTrigger && (scoreConsume || (pendingScore != PENDING_SCORE_MAX[2:0]));
  assign failArrive   = failTrigger;

  always_comb begin
    case ({scoreArrive, scoreConsume})
      2'b10:   pendingScoreNext = pendingScore + 3'd1;
      2'b01:   pendingScoreNext = pendingScore - 3'd1;
      default: pendingScoreNext = pendingScore;   // neither, or both (nets to no change)
    endcase
  end

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      state           <= S_IDLE;
      melodySelectReg <= '0;
      pendingScore    <= '0;
      pendingFail     <= 1'b0;
    end else begin
      pendingScore <= pendingScoreNext;
      pendingFail  <= failArrive || (pendingFail && !failConsume);

      case (state)
        S_IDLE: begin
          if (pendingFail) begin
            melodySelectReg <= FAIL_MELODY;
            state           <= S_SET;
          end else if (pendingScore != 3'd0) begin
            melodySelectReg <= SCORE_MELODY;
            state           <= S_SET;
          end
        end
        S_SET:  state <= S_FIRE;
        S_FIRE: state <= S_WAIT;
        S_WAIT: if (melodyEnded) state <= S_IDLE;
        default: state <= S_IDLE;
      endcase
    end
  end

  assign playingScore = (state == S_WAIT) && (melodySelectReg == SCORE_MELODY);
  assign playingFail  = (state == S_WAIT) && (melodySelectReg == FAIL_MELODY);

  // ---------------------------------------------------------------- supplied audio chain, unmodified
  melody_player_1 player (
      .resetN       (resetN),
      .CLOCK_31p5   (clk),
      .startMelody  (startMelody),
      .melodySelect (melodySelectReg),
      .tone         (tone),
      .octave       (octave),
      .EnableSoundOut(enableSoundOut),
      .melodyEnded  (melodyEnded)
  );

  logic [11:0] preScaleValue;

  ToneDecoder toneDecoder (
      .tone         (tone),
      .octave       (octave),
      .preScaleValue(preScaleValue)
  );

  logic slowEnPulse, slowEnPulseD;

  prescaler presc (
      .clk         (clk),
      .resetN      (resetN),
      .preScaleValue(preScaleValue),
      .slowEnPulse (slowEnPulse),
      .slowEnPulse_d(slowEnPulseD)
  );

  logic [7:0] sinAddr;

  addr_counter #(.COUNT_SIZE(8)) addrCounter (
      .clk   (clk),
      .resetN(resetN),
      .en    (slowEnPulse),
      .en1   (enableSoundOut),
      .addr  (sinAddr)
  );

  logic [15:0] sinVal;

  sintable #(.COUNT_SIZE(8)) sineTable (
      .clk   (clk),
      .resetN(resetN),
      .ADDR  (sinAddr),
      .volume(1'b1),      // full scale; muting is done below, once, at the output
      .Q     (sinVal)
  );

  // ---------------------------------------------------------------- output
  // Muting only zeroes the sample sent to the codec: it cannot affect the
  // arbiter, the melody state machine, or anything upstream of this line.
  assign audioSample = mute ? 16'sd0 : sinVal;

endmodule
