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

endpackage
