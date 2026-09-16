// Shared definitions of the on-chip neural network (and, from M10, the trainer).
//
// Network: 4 inputs -> 6 hard-tanh neurons -> 1 linear output -> UP/HOLD/DOWN.
// Every gene is a signed 8-bit number. Gene layout (37 genes):
//   hidden neuron j (0..5): gene 5j = bias, genes 5j+1..5j+4 = weights of F0..F3
//   output neuron:          gene 30 = bias, genes 31..36 = weights of h0..h5
//
// Fixed-point formats:
//   features, hidden outputs  Q1.6  (value / 64)
//   weights, biases           Q2.5  (value / 32)
//   products, sums            Q.11  (value / 2048), 18-bit accumulator

package ml_pkg;
  import game_params_pkg::*;

  // ---------------------------------------------------------------- network shape
  localparam int NN_INPUTS   = 4;
  localparam int NN_HIDDEN   = 6;
  localparam int NN_GENES    = NN_HIDDEN * (NN_INPUTS + 1) + NN_HIDDEN + 1;   // 37
  localparam int GENE_ADDR_W = 6;
  localparam int ACC_W       = 18;

  localparam int H_LIMIT     = 64;      // hard-tanh output limit (1.0)
  localparam int THETA       = 512;     // output dead zone (0.25): |y| <= THETA means HOLD

  // Action code used by the network, the training lanes and control_mux:
  // bit 1 = move the maze up, bit 0 = move it down.
  localparam logic [1:0] ACT_HOLD = 2'b00;
  localparam logic [1:0] ACT_DOWN = 2'b01;
  localparam logic [1:0] ACT_UP   = 2'b10;

  // ---------------------------------------------------------------- features
  localparam int BIRD_HB_CENTRE = (BIRD_HB_Y0 + BIRD_HB_Y1) / 2;             // 17
  localparam int HB_RIGHT       = BIRD_X + BIRD_HB_X1;                        // 169
  // A column still has to be passed while its collision core reaches the hitbox:
  // the same test obstacle scoring uses (colX + CORAL_W - CORAL_CORE_INSET > hitbox left).
  localparam int NOT_PASSED_X   = BIRD_X + BIRD_HB_X0 - CORAL_W + CORAL_CORE_INSET + 1;   // 94
  localparam int TAU_MAX        = 127;
  localparam int ALIGN_TOL      = 16;   // px: the fitness counts steps this well centred

  // Frames per pixel of scrolling, x256, for each world speed level:
  // round(256 * 64 / worldStep) with worldStep = WORLD_STEP_BASE + level * WORLD_STEP_INCREMENT.
  // tb_features checks these against game_params_pkg.
  localparam logic [8:0] TAU_RECIP_0 = 9'd256;
  localparam logic [8:0] TAU_RECIP_1 = 9'd171;
  localparam logic [8:0] TAU_RECIP_2 = 9'd128;
  localparam logic [8:0] TAU_RECIP_3 = 9'd102;
  localparam logic [8:0] TAU_RECIP_4 = 9'd85;
  localparam logic [8:0] TAU_RECIP_5 = 9'd73;
  localparam logic [8:0] TAU_RECIP_6 = 9'd64;
  localparam logic [8:0] TAU_RECIP_7 = 9'd57;

  // ---------------------------------------------------------------- on-chip trainer (M10)
  localparam int LANES       = 8;       // candidates simulated in parallel
  localparam int POP_SIZE    = 64;      // candidates per generation (8 batches)
  localparam int CAND_W      = 6;
  localparam int T_MAX       = 4095;    // PLAY steps after which a run counts as completed
  localparam int READY_STEPS = 88;      // frozen "GET READY" steps before PLAY (as game_fsm)
  localparam int STEP_CLOCKS = 48;      // clocks per simulated step (move .. new action)
  localparam int FIT_W       = 26;      // fitness = {gates[9:0], survival + centred steps[15:0]}
  localparam int RUNS_TRAIN  = 2;       // worlds A and B of the generation

  // Fixed world seeds. Bit 15 is 1, so they can never equal a training seed
  // (training seeds have bit 15 = 0). V1..V4 = entries 0..3 (validation, M11),
  // T1..T8 = entries 4..11 (final test, M11). Entry i = FIXED_SEEDS[16 * i +: 16].
  localparam logic [191:0] FIXED_SEEDS = {
      16'hF5B7, 16'hE2A4, 16'hD0F1, 16'hCDEF, 16'hBABC, 16'hA789, 16'h9456, 16'h8123,   // T8..T1
      16'hC659, 16'hB4E2, 16'h9D71, 16'h8A3C                                            // V4..V1
  };

  // Simulation speed levels (TRAIN AI, Numpad 4 faster / 6 slower): clocks
  // between step starts. Level 0 = one step per VGA frame (real time).
  // x1, x2, x4, x16, x64, x256, x1024, MAX
  function automatic logic [18:0] sim_period(input logic [2:0] level);
    case (level)
      3'd0:    return 19'd433993;
      3'd1:    return 19'd216997;
      3'd2:    return 19'd108498;
      3'd3:    return 19'd27125;
      3'd4:    return 19'd6781;
      3'd5:    return 19'd1695;
      3'd6:    return 19'd424;
      default: return 19'd0;          // MAX: back to back
    endcase
  endfunction

  // What the trainer is doing (training screen words STAGE and RUNSTATE).
  localparam logic [2:0] STG_IDLE     = 3'd0;
  localparam logic [2:0] STG_TRAINING = 3'd1;
  localparam logic [2:0] STG_VALIDATE = 3'd2;
  localparam logic [2:0] STG_TESTING  = 3'd3;
  localparam logic [2:0] STG_EVOLVING = 3'd4;
  localparam logic [2:0] STG_COMPLETE = 3'd5;

  localparam logic [2:0] RS_LOADING   = 3'd0;
  localparam logic [2:0] RS_READY     = 3'd1;
  localparam logic [2:0] RS_PLAYING   = 3'd2;
  localparam logic [2:0] RS_FINISHED  = 3'd3;
  localparam logic [2:0] RS_SCORING   = 3'd4;
  localparam logic [2:0] RS_NEXT_GEN  = 3'd5;
  localparam logic [2:0] RS_PAUSED    = 3'd6;
  localparam logic [2:0] RS_NONE      = 3'd7;

  // Lane states shown on the training screen.
  localparam logic [1:0] LANE_IDLE  = 2'd0;
  localparam logic [1:0] LANE_ALIVE = 2'd1;
  localparam logic [1:0] LANE_DEAD  = 2'd2;
  localparam logic [1:0] LANE_DONE  = 2'd3;

endpackage
