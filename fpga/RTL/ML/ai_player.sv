// The AI that plays the visible game (WATCH AI).
//
// Once per frame, right after the game has updated (tickState), it reads the
// game state, evaluates the network stored in its weight memory and presents
// UP / HOLD / DOWN until the next frame's move. It uses the same feature and
// network modules as the on-chip trainer's lanes, and it steers through the
// same maze_control inputs as Numpad 8 / 2.
//
// Frame timeline (clocks after tickState): +1 world features, +2 player
// features, +3 start, +42 new action. A frame is 433,993 clocks long.
//
// The weight memory is a single-port RAM visible to Quartus' In-System Memory
// Content Editor as "WTCH" (weights can be read or written over JTAG). It is
// loaded from NET_FILE at configuration and can be overwritten through the
// write port (a committed training result, M12). It has no reset, so its
// contents survive KEY0.

module ai_player
  import game_params_pkg::*, ml_pkg::*;
#(
    parameter NET_FILE = "RTL/MIF/nn_demo.mif"
) (
    input  logic                         clk,
    input  logic                         resetN,
    input  logic                         enable,       // AI mode
    input  logic                         tickState,

    input  logic signed [10:0]           birdY,
    input  logic signed [11:0]           birdVy,
    input  logic [NUM_COLUMNS-1:0]       colActive,
    input  logic [NUM_COLUMNS-1:0][10:0] colX,
    input  logic [NUM_COLUMNS-1:0][9:0]  gapTop,
    input  logic signed [4:0]            mazeVy,
    input  logic [2:0]                   speedLevel,

    // weight memory write port (writes win over the evaluation)
    input  logic                         netWe,
    input  logic [GENE_ADDR_W-1:0]       netWa,
    input  logic [7:0]                   netWd,

    output logic                         aiUp,
    output logic                         aiDown,
    output logic                         aiValid,      // an action has been computed

    // for the debug overlay
    output logic [NN_INPUTS-1:0][7:0]    feat,
    output logic signed [ACC_W-1:0]      y,
    output logic signed [7:0]            h0
);

  logic sampleW, sampleL, start;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      sampleW <= 1'b0;
      sampleL <= 1'b0;
      start   <= 1'b0;
    end else begin
      sampleW <= tickState && enable;
      sampleL <= sampleW;
      start   <= sampleL;
    end
  end

  // ---------------------------------------------------------------- features
  logic [1:0]         next1, next2;
  logic               vis1, use2;
  logic [6:0]         tau;
  logic signed [10:0] birdC;
  logic signed [11:0] birdVyW;

  feature_world world (
      .clk(clk), .resetN(resetN), .sample(sampleW),
      .birdY(birdY), .birdVy(birdVy), .colActive(colActive), .colX(colX), .speedLevel(speedLevel),
      .next1(next1), .next2(next2), .vis1(vis1), .use2(use2), .tau(tau),
      .birdC(birdC), .birdVyOut(birdVyW));

  feature_lane lane (
      .clk(clk), .resetN(resetN), .sample(sampleL),
      .next1(next1), .next2(next2), .vis1(vis1), .use2(use2), .tau(tau),
      .birdC(birdC), .birdVy(birdVyW), .gapTop(gapTop), .mazeVy(mazeVy),
      .feat(feat), .aligned(), .eNext());

  // ---------------------------------------------------------------- network
  logic [GENE_ADDR_W-1:0] geneAddr;
  logic                   opLoad, opAdd, latchH, decide, busy;
  logic [3:0]             inSel;
  logic [2:0]             hIdx;
  logic [7:0]             gene;

  nn_sched sched (
      .clk(clk), .resetN(resetN), .start(start), .geneAddr(geneAddr),
      .opLoad(opLoad), .opAdd(opAdd), .inSel(inSel), .latchH(latchH), .hIdx(hIdx),
      .decide(decide), .busy(busy));

  altsyncram #(
      .operation_mode               ("SINGLE_PORT"),
      .width_a                      (8),
      .widthad_a                    (GENE_ADDR_W),
      .numwords_a                   (1 << GENE_ADDR_W),
      .init_file                    (NET_FILE),
      .intended_device_family       ("Cyclone V"),
      .lpm_hint                     ("ENABLE_RUNTIME_MOD=YES,INSTANCE_NAME=WTCH"),
      .lpm_type                     ("altsyncram"),
      .outdata_aclr_a               ("NONE"),
      .outdata_reg_a                ("UNREGISTERED"),
      .power_up_uninitialized       ("FALSE"),
      .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
      .ram_block_type               ("M10K")
  ) weights (
      .address_a     (netWe ? netWa : geneAddr),
      .clock0        (clk),
      .data_a        (netWd),
      .wren_a        (netWe),
      .q_a           (gene),
      .aclr0         (1'b0),
      .aclr1         (1'b0),
      .address_b     (1'b1),
      .addressstall_a(1'b0),
      .addressstall_b(1'b0),
      .byteena_a     (1'b1),
      .byteena_b     (1'b1),
      .clock1        (1'b1),
      .clocken0      (1'b1),
      .clocken1      (1'b1),
      .clocken2      (1'b1),
      .clocken3      (1'b1),
      .data_b        (1'b1),
      .eccstatus     (),
      .q_b           (),
      .rden_a        (1'b1),
      .rden_b        (1'b1),
      .wren_b        (1'b0)
  );

  logic [1:0]                act;
  logic [NN_HIDDEN-1:0][7:0] hidden;

  nn_datapath unit (
      .clk(clk), .resetN(resetN), .enable(1'b1), .clear(!enable),
      .gene(gene), .feat(feat),
      .opLoad(opLoad), .opAdd(opAdd), .inSel(inSel), .latchH(latchH), .hIdx(hIdx), .decide(decide),
      .act(act), .y(y), .hidden(hidden));

  assign h0     = $signed(hidden[0]);
  assign aiUp   = act[1];
  assign aiDown = act[0];

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN)      aiValid <= 1'b0;
    else if (!enable) aiValid <= 1'b0;
    else if (decide)  aiValid <= 1'b1;
  end

endmodule
