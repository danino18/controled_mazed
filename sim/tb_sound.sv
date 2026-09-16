// Checks sound_engine: exactly one sound per score/collision event, no
// retriggering while a sound is already playing or while the game stays in
// GAME_OVER, distinct score vs. failure tones, and SW0 mute. Runs the real
// supplied audio chain (melody_player_1's simulation-timing copy in
// sim/models, ToneDecoder/prescaler/addr_counter/sintable unmodified).
//
// The arbiter takes a few clocks to go from a trigger pulse to the sound
// actually starting (one cycle for pendingScore/pendingFail to register, one
// to settle melodySelect before melody_player_1's registered-address ROM
// read, one for startMelody, one for melody_player_1's own state machine to
// react) -- every check below waits for that with wait_start() rather than
// sampling playingScore/playingFail immediately after the trigger.
`timescale 1ns / 1ps

module tb_sound;

  logic clk = 1'b0;
  logic resetN = 1'b0;
  always #5 clk = ~clk;

  logic        scoreTrigger = 1'b0, failTrigger = 1'b0, mute = 1'b0;
  logic [15:0] audioSample;
  logic        playingScore, playingFail;

  sound_engine dut (
      .clk(clk), .resetN(resetN), .scoreTrigger(scoreTrigger), .failTrigger(failTrigger),
      .mute(mute), .audioSample(audioSample), .playingScore(playingScore), .playingFail(playingFail));

  int errors = 0;
  int scorePlays = 0, failPlays = 0;
  logic playingScorePrev = 1'b0, playingFailPrev = 1'b0;

  // Count each time a sound STARTS (rising edge of playingScore/playingFail),
  // so "exactly one sound event" is checked the same way an ear would hear it.
  always @(posedge clk) begin
    if (playingScore && !playingScorePrev) scorePlays++;
    if (playingFail  && !playingFailPrev)  failPlays++;
    playingScorePrev <= playingScore;
    playingFailPrev  <= playingFail;
  end

  task automatic fail_msg(input string msg);
    errors++;
    if (errors < 20) $display("FAIL: %s", msg);
  endtask

  task automatic pulse(ref logic sig);
    @(negedge clk);
    sig = 1'b1;
    @(negedge clk);
    sig = 1'b0;
  endtask

  // Waits for a sound to start (a few clocks of arbiter/ROM pipeline), or
  // flags a failure if neither ever starts within the timeout.
  task automatic wait_start(input int maxClocks);
    int n;
    n = 0;
    while (!playingScore && !playingFail && n < maxClocks) begin
      @(posedge clk);
      n++;
    end
    if (!playingScore && !playingFail) fail_msg("no sound started within the expected startup window");
  endtask

  // Runs clocks until nothing is playing AND nothing remains queued (both
  // jingles are well under 1 s of simulated audio time at the sim-mode tick).
  // Checking only playingScore/playingFail is not enough: state passes
  // through S_IDLE for exactly one transient clock between two back-to-back
  // queued plays, so a check that stopped there would report "silent" while
  // items are still waiting to play.
  task automatic wait_silent(input int maxClocks);
    int n;
    n = 0;
    while ((playingScore || playingFail || dut.pendingScore != 0 || dut.pendingFail) && n < maxClocks) begin
      @(posedge clk);
      n++;
    end
    if (playingScore || playingFail || dut.pendingScore != 0 || dut.pendingFail)
      fail_msg("sound_engine never returned to silence (or never drained its queue)");
  endtask

  // Triggers one sound, waits for it to start and finish, and reports its
  // duration and peak |amplitude| -- used to confirm score and fail don't
  // sound alike (different duration/peak catches "same melody" mistakes).
  task automatic play_and_measure(ref logic trigger, output int durationClocks, output int peak);
    durationClocks = 0;
    peak = 0;
    pulse(trigger);
    wait_start(50);
    while (playingScore || playingFail) begin
      int mag;
      mag = $signed(audioSample) < 0 ? -$signed(audioSample) : $signed(audioSample);
      if (mag > peak) peak = mag;
      @(posedge clk);
      durationClocks++;
    end
  endtask

  initial begin
    int d1, p1, d2, p2;

    repeat (3) @(negedge clk);
    resetN = 1'b1;

    // ---------------------------------------------------------------- one event -> one sound
    if (playingScore || playingFail) fail_msg("a sound is already playing before any trigger");
    pulse(scoreTrigger);
    wait_start(50);
    if (!playingScore) fail_msg("score trigger did not start the score jingle");
    if (playingFail) fail_msg("score trigger started the fail tone");
    wait_silent(200000);
    if (scorePlays != 1 || failPlays != 0) fail_msg($sformatf("after one score event: scorePlays=%0d failPlays=%0d, expected 1 0", scorePlays, failPlays));

    pulse(failTrigger);
    wait_start(50);
    if (!playingFail) fail_msg("fail trigger did not start the failure tone");
    if (playingScore) fail_msg("fail trigger started the score jingle");
    wait_silent(200000);
    if (scorePlays != 1 || failPlays != 1) fail_msg($sformatf("after one fail event: scorePlays=%0d failPlays=%0d, expected 1 1", scorePlays, failPlays));

    // ---------------------------------------------------------------- must not continuously retrigger
    // A trigger held (or repeated) while GAME_OVER/HIT would stay busy is not
    // itself sound_engine's job (game_fsm only pulses roundOver once per
    // collision - see tb_game_fsm), but sound_engine must still not restart a
    // sound that is already playing just because playingFail stays high.
    pulse(failTrigger);
    wait_start(50);
    repeat (50) @(posedge clk);   // well inside the fail tone's own duration
    if (failPlays != 2) fail_msg($sformatf("fail tone retriggered on its own while playing: failPlays=%0d, expected 2", failPlays));
    wait_silent(200000);

    // ---------------------------------------------------------------- queued events are not lost
    pulse(scoreTrigger);
    repeat (3) @(posedge clk);
    pulse(scoreTrigger);          // arrives while the first is still playing/queued
    pulse(scoreTrigger);
    wait_start(50);                // else wait_silent could see "not playing yet" and return at once
    wait_silent(400000);
    if (scorePlays != 4) fail_msg($sformatf("3 more score triggers in quick succession gave scorePlays=%0d, expected 4 total", scorePlays));

    // fail arriving while a score is playing: fail takes priority but the
    // queued score is not lost, both eventually play exactly once each.
    pulse(scoreTrigger);
    repeat (3) @(posedge clk);
    pulse(failTrigger);
    wait_start(50);
    wait_silent(400000);
    if (scorePlays != 5 || failPlays != 3)
      fail_msg($sformatf("overlapping score+fail: scorePlays=%0d failPlays=%0d, expected 5 3", scorePlays, failPlays));

    // ---------------------------------------------------------------- score and fail sound different
    play_and_measure(scoreTrigger, d1, p1);
    play_and_measure(failTrigger, d2, p2);
    $display("INFO: score jingle: %0d clocks, peak amplitude %0d", d1, p1);
    $display("INFO: fail tone:    %0d clocks, peak amplitude %0d", d2, p2);
    if (d1 == d2) fail_msg("score and fail sounds have the exact same duration");
    if (p1 == 0 || p2 == 0) fail_msg("a sound produced a silent (all-zero) waveform");

    // ---------------------------------------------------------------- SW0 mute
    mute = 1'b0;
    pulse(scoreTrigger);
    wait_start(50);
    if (!playingScore) fail_msg("setup: score not playing before mute test");
    mute = 1'b1;
    repeat (2) @(posedge clk);    // combinational mux, settles immediately
    if (audioSample != 16'sd0) fail_msg("SW0 mute did not force the sample to zero while a sound plays");
    if (!playingScore) fail_msg("mute incorrectly stopped the arbiter/melody state (should only silence the sample)");
    wait_silent(200000);
    if (scorePlays != 7) fail_msg($sformatf("muted sound did not still count as having played: scorePlays=%0d, expected 7 (mute must not affect the game-side event)", scorePlays));
    mute = 1'b0;

    // and mute must not block the NEXT sound from starting either
    pulse(scoreTrigger);
    mute = 1'b1;
    wait_start(50);
    if (!playingScore) fail_msg("mute prevented a new sound from starting");
    wait_silent(200000);
    mute = 1'b0;

    if (errors == 0) $display("PASS: tb_sound");
    else             $display("FAIL: tb_sound (%0d errors)", errors);
    $finish;
  end

endmodule
