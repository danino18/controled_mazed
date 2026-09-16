// One neural network evaluation unit (4 -> 6 -> 1), serial multiply-accumulate.
// It has its own multiplier and accumulator; the weights come from a memory
// addressed by nn_sched, which also supplies the control signals.
//
//   hidden:  h_j = clamp((b_j << 6 + sum_i F_i * w_ji) >>> 5, -64, +64)
//   output:  y   = b_o << 6 + sum_j h_j * v_j
//   action:  UP if y > THETA, DOWN if y < -THETA, otherwise HOLD
//
// The 18-bit accumulator cannot overflow: |b << 6| <= 8192 and each product is
// at most 128 * 128 = 16384, so a hidden sum stays within 73,728 and the
// output sum within 57,344 (both below 2^17).
// While enable is low (a dead training lane) nothing changes, so the last
// action stays visible.

module nn_datapath
  import ml_pkg::*;
(
    input  logic                        clk,
    input  logic                        resetN,
    input  logic                        enable,
    input  logic                        clear,     // new round: action back to HOLD
    input  logic [7:0]                  gene,      // weight memory output
    input  logic [NN_INPUTS-1:0][7:0]   feat,
    input  logic                        opLoad,
    input  logic                        opAdd,
    input  logic [3:0]                  inSel,
    input  logic                        latchH,
    input  logic [2:0]                  hIdx,
    input  logic                        decide,
    output logic [1:0]                  act,
    output logic signed [ACC_W-1:0]     y,         // output sum of the last evaluation
    output logic [NN_HIDDEN-1:0][7:0]   hidden     // hidden outputs of the last evaluation
);

  logic signed [7:0]       in;
  logic signed [7:0]       w;
  (* multstyle = "dsp" *) logic signed [15:0] prod;
  logic signed [ACC_W-1:0] acc;
  logic signed [ACC_W-1:0] shifted;
  logic signed [7:0]       squashed;

  assign w  = $signed(gene);
  assign in = (inSel < 4'd4) ? $signed(feat[inSel[1:0]]) : $signed(hidden[inSel - 4'd4]);
  assign prod = in * w;

  assign shifted  = acc >>> 5;
  assign squashed = (shifted >  H_LIMIT) ? 8'(H_LIMIT)  :
                    (shifted < -H_LIMIT) ? 8'(-H_LIMIT) : 8'(shifted);

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      acc    <= '0;
      hidden <= '0;
      y      <= '0;
      act    <= ACT_HOLD;
    end else if (clear) begin
      act    <= ACT_HOLD;
    end else if (enable) begin
      if (latchH) hidden[hIdx] <= squashed;
      if (opLoad)     acc <= ACC_W'(w) <<< 6;
      else if (opAdd) acc <= acc + ACC_W'(prod);
      if (decide) begin
        y <= acc;
        if (acc > THETA)       act <= ACT_UP;
        else if (acc < -THETA) act <= ACT_DOWN;
        else                   act <= ACT_HOLD;
      end
    end
  end

endmodule
