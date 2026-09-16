// Training scheduler (M10: evaluation of a fixed population).
//
// A pass ("generation") evaluates all POP_SIZE candidates in batches of LANES:
//
//   GEN_START   draw this generation's training worlds A and B (world_seeds);
//               clear the generation statistics and the top-8 list
//   LOAD        lanes <- candidates 8*batch .. 8*batch+7 (population memory
//               -> lane weight memory)
//   RUN_START   run r (r = 0: world A, r = 1: world B); on r = 0 the lane
//               accumulators are cleared and the lane labels change
//   RUN         train_lanes plays the run
//   HOLD_RUN    "RUN FINISHED" pause (0.5 s at SIM x1 .. x16)
//   STORE       per lane: fitness memory[candidate] <- fitness, top-8 insert,
//               generation best and survival sum
//   NEXT_BATCH  next batch, or GEN_END: mean survival, generation + 1
//   HOLD_GEN    "NEXT GENERATION" pause (1 s at SIM x1 .. x16)
//
// Every candidate of a generation therefore plays exactly worlds A_g and B_g,
// and the worlds change from one generation to the next (decision D3). M11
// adds evolution, validation and the final test between GEN_END and GEN_START.
//
// The population memory is initialised from POP_FILE (in-system memory
// editor name POPA), the fitness memory is FIT.

module train_ctrl
  import game_params_pkg::*, ml_pkg::*;
#(
    parameter     POP_FILE        = "RTL/MIF/pop_init.mif",
    parameter int HOLD_RUN_FRAMES = 36,
    parameter int HOLD_GEN_FRAMES = 73
) (
    input  logic                         clk,
    input  logic                         resetN,

    input  logic                         start,         // one clock: begin training
    input  logic                         abort,         // one clock: stop at once
    input  logic [15:0]                  runIdIn,       // entropy latched when training starts
    input  logic                         frameTick,     // one clock per VGA frame (pauses only)
    input  logic [2:0]                   simLevel,

    // simulator
    output logic                         runStart,
    output logic [15:0]                  runSeed,
    output logic [LANES-1:0]             laneEnable,
    output logic                         stageClear,
    input  logic                         runDone,
    input  logic [LANES-1:0][9:0]        accG,
    input  logic [LANES-1:0][15:0]       accTA,
    input  logic [LANES-1:0][14:0]       accT,

    output logic                         laneWe,
    output logic [GENE_ADDR_W-1:0]       laneWa,
    output logic [LANES*8-1:0]           laneWd,

    // status (for the display)
    output logic                         active,        // training is running
    output logic [2:0]                   stage,         // STG_*
    output logic [2:0]                   runState,      // RS_* (RS_READY also stands for a run in progress)
    output logic [15:0]                  runId,
    output logic [7:0]                   gen,
    output logic [3:0]                   batch,         // 0..7
    output logic [3:0]                   runIdx,        // 0 = world A, 1 = world B
    output logic [15:0]                  seedA,
    output logic [15:0]                  seedB,
    output logic [LANES-1:0][CAND_W-1:0] laneCand,
    output logic [FIT_W-1:0]             genBest,
    output logic [CAND_W-1:0]            genBestCand,
    output logic                         genBestValid,
    output logic [21:0]                  genSumT,       // survival steps of the generation so far
    output logic [6:0]                   genDone,       // candidates scored in this generation
    output logic [6:0]                   lastMeanSurv,  // mean survival % of the previous generation
    output logic                         lastMeanValid,
    output logic [7:0][FIT_W-1:0]        topScores,
    output logic [7:0][CAND_W-1:0]       topIds,
    output logic [7:0]                   topValid,
    output logic [31:0]                  evaluated,     // candidate evaluations completed
    output logic                         genPulse       // one clock per finished generation
);

  typedef enum logic [3:0] {
      S_IDLE, S_SEED, S_GEN_START, S_DRAW_B, S_DRAWN, S_LOAD, S_RUN_START, S_RUN, S_HOLD_RUN,
      S_RUN_END, S_STORE, S_NEXT_BATCH, S_GEN_END, S_HOLD_GEN
  } state_t;

  state_t state;

  // ---------------------------------------------------------------- world seeds
  logic        seedLoad, seedDraw;

  // world_seeds draws at the end of GEN_START (A) and DRAW_B (B)
  assign seedDraw = (state == S_GEN_START) || (state == S_DRAW_B);
  logic [15:0] drawn;

  world_seeds seeds (
      .clk   (clk),
      .resetN(resetN),
      .load  (seedLoad),
      .runId (runId),
      .draw  (seedDraw),
      .seed  (drawn)
  );

  // ---------------------------------------------------------------- population memory
  logic [CAND_W+GENE_ADDR_W-1:0] popRa;
  logic [7:0]                    popQ;

  altsyncram #(
      .operation_mode        ("DUAL_PORT"),
      .width_a               (8),
      .widthad_a             (CAND_W + GENE_ADDR_W),
      .numwords_a            (1 << (CAND_W + GENE_ADDR_W)),
      .width_b               (8),
      .widthad_b             (CAND_W + GENE_ADDR_W),
      .numwords_b            (1 << (CAND_W + GENE_ADDR_W)),
      .address_reg_b         ("CLOCK0"),
      .outdata_reg_b         ("UNREGISTERED"),
      .outdata_aclr_b        ("NONE"),
      .init_file             (POP_FILE),
      .intended_device_family("Cyclone V"),
      .lpm_type              ("altsyncram"),
      .lpm_hint              ("ENABLE_RUNTIME_MOD=NO"),
      .power_up_uninitialized("FALSE"),
      .read_during_write_mode_mixed_ports("DONT_CARE"),
      .ram_block_type        ("M10K")
  ) population (
      .clock0        (clk),
      .wren_a        (1'b0),
      .address_a     ({(CAND_W + GENE_ADDR_W){1'b0}}),
      .data_a        (8'h00),
      .address_b     (popRa),
      .q_b           (popQ),
      .aclr0         (1'b0),
      .aclr1         (1'b0),
      .addressstall_a(1'b0),
      .addressstall_b(1'b0),
      .byteena_a     (1'b1),
      .byteena_b     (1'b1),
      .clock1        (1'b1),
      .clocken0      (1'b1),
      .clocken1      (1'b1),
      .clocken2      (1'b1),
      .clocken3      (1'b1),
      .data_b        (8'hFF),
      .eccstatus     (),
      .q_a           (),
      .rden_a        (1'b1),
      .rden_b        (1'b1),
      .wren_b        (1'b0)
  );

  // ---------------------------------------------------------------- fitness memory
  logic                 fitWe;
  logic [CAND_W-1:0]    fitWa;
  logic [FIT_W-1:0]     fitWd;

  altsyncram #(
      .operation_mode        ("DUAL_PORT"),
      .width_a               (FIT_W),
      .widthad_a             (CAND_W),
      .numwords_a            (POP_SIZE),
      .width_b               (FIT_W),
      .widthad_b             (CAND_W),
      .numwords_b            (POP_SIZE),
      .address_reg_b         ("CLOCK0"),
      .outdata_reg_b         ("UNREGISTERED"),
      .outdata_aclr_b        ("NONE"),
      .intended_device_family("Cyclone V"),
      .lpm_type              ("altsyncram"),
      .power_up_uninitialized("FALSE"),
      .read_during_write_mode_mixed_ports("DONT_CARE"),
      .ram_block_type        ("M10K")
  ) fitness (
      .clock0        (clk),
      .wren_a        (fitWe),
      .address_a     (fitWa),
      .data_a        (fitWd),
      .address_b     ({CAND_W{1'b0}}),
      .q_b           (),
      .aclr0         (1'b0),
      .aclr1         (1'b0),
      .addressstall_a(1'b0),
      .addressstall_b(1'b0),
      .byteena_a     (1'b1),
      .byteena_b     (1'b1),
      .clock1        (1'b1),
      .clocken0      (1'b1),
      .clocken1      (1'b1),
      .clocken2      (1'b1),
      .clocken3      (1'b1),
      .data_b        ({FIT_W{1'b1}}),
      .eccstatus     (),
      .q_a           (),
      .rden_a        (1'b1),
      .rden_b        (1'b1),
      .wren_b        (1'b0)
  );

  // ---------------------------------------------------------------- top 8 of the generation
  logic                 topClear, topInsert;
  logic [FIT_W-1:0]     topScore;
  logic [CAND_W-1:0]    topId;

  top8_list top8 (
      .clk   (clk),
      .resetN(resetN),
      .clear (topClear),
      .insert(topInsert),
      .score (topScore),
      .id    (topId),
      .scores(topScores),
      .ids   (topIds),
      .valid (topValid)
  );

  // ---------------------------------------------------------------- scheduler
  logic [5:0]               g;          // gene being copied
  logic [3:0]               k;          // lane being read / stored
  logic [LANES*8-1:0]       word;
  logic [7:0]               holdCount;
  logic [LANES-1:0][CAND_W-1:0] loadCand;
  logic                     slow;

  assign slow = (simLevel <= 3'd3);    // x1 .. x16: visible pauses

  always_comb begin
    for (int i = 0; i < LANES; i++) loadCand[i] = CAND_W'({batch[2:0], 3'(i)});
  end

  // population read address while copying: candidate of lane k, gene g
  assign popRa  = {loadCand[k[2:0]], g};
  assign laneWe = (state == S_LOAD) && (k == 4'd9);
  assign laneWa = g;
  assign laneWd = word;

  // fitness of lane k (combinational, used in S_STORE)
  logic [FIT_W-1:0] laneFit;
  assign laneFit = {accG[k[2:0]], accTA[k[2:0]]};

  assign fitWe     = (state == S_STORE);
  assign fitWa     = laneCand[k[2:0]];
  assign fitWd     = laneFit;
  assign topInsert = (state == S_STORE);
  assign topScore  = laneFit;
  assign topId     = laneCand[k[2:0]];
  assign topClear  = (state == S_GEN_START);

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      state         <= S_IDLE;
      runStart      <= 1'b0;
      runSeed       <= '0;
      laneEnable    <= '0;
      stageClear    <= 1'b0;
      seedLoad      <= 1'b0;
      runId         <= '0;
      gen           <= '0;
      batch         <= '0;
      runIdx        <= '0;
      seedA         <= '0;
      seedB         <= '0;
      laneCand      <= '0;
      genBest       <= '0;
      genBestCand   <= '0;
      genBestValid  <= 1'b0;
      genSumT       <= '0;
      genDone       <= '0;
      lastMeanSurv  <= '0;
      lastMeanValid <= 1'b0;
      evaluated     <= '0;
      genPulse      <= 1'b0;
      g             <= '0;
      k             <= '0;
      word          <= '0;
      holdCount     <= '0;
    end else begin
      runStart   <= 1'b0;
      stageClear <= 1'b0;
      seedLoad   <= 1'b0;
      genPulse   <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start) begin
            runId    <= runIdIn;
            seedLoad <= 1'b1;
            gen      <= '0;
            lastMeanValid <= 1'b0;
            evaluated <= '0;
            state    <= S_SEED;
          end
        end

        S_SEED: state <= S_GEN_START;       // world_seeds takes the RUN ID on this clock

        S_GEN_START: begin                  // A is drawn on this clock
          batch        <= '0;
          genBest      <= '0;
          genBestValid <= 1'b0;
          genSumT      <= '0;
          genDone      <= '0;
          state        <= S_DRAW_B;
        end

        S_DRAW_B: begin                     // A is ready; B is drawn on this clock
          seedA <= drawn;
          state <= S_DRAWN;
        end

        S_DRAWN: begin
          seedB <= drawn;
          g     <= '0;
          k     <= '0;
          state <= S_LOAD;
        end

        // Gene g of lanes 0..7: address k = 0..7, capture k = 1..8, write at k = 9.
        S_LOAD: begin
          if (k >= 4'd1 && k <= 4'd8) word[(int'(k) - 1) * 8 +: 8] <= popQ;
          if (k == 4'd9) begin
            k <= '0;
            if (g == 6'(NN_GENES - 1)) begin
              g      <= '0;
              runIdx <= '0;
              state  <= S_RUN_START;
            end else begin
              g <= g + 6'd1;
            end
          end else begin
            k <= k + 4'd1;
          end
        end

        S_RUN_START: begin
          runStart   <= 1'b1;
          runSeed    <= (runIdx == 4'd0) ? seedA : seedB;
          laneEnable <= '1;
          if (runIdx == 4'd0) begin
            stageClear <= 1'b1;
            laneCand   <= loadCand;
          end
          state <= S_RUN;
        end

        S_RUN: begin
          if (runDone) begin
            holdCount <= '0;
            state     <= S_HOLD_RUN;
          end
        end

        S_HOLD_RUN: begin
          if (!slow || holdCount >= 8'(HOLD_RUN_FRAMES)) state <= S_RUN_END;
          else if (frameTick) holdCount <= holdCount + 8'd1;
        end

        S_RUN_END: begin
          if (runIdx == 4'(RUNS_TRAIN - 1)) begin
            k     <= '0;
            state <= S_STORE;
          end else begin
            runIdx <= runIdx + 4'd1;
            state  <= S_RUN_START;
          end
        end

        S_STORE: begin                      // lane k: fitness memory, top-8, statistics
          genSumT <= genSumT + 22'(accT[k[2:0]]);
          if (!genBestValid || laneFit > genBest) begin
            genBest      <= laneFit;
            genBestCand  <= laneCand[k[2:0]];
            genBestValid <= 1'b1;
          end
          evaluated <= evaluated + 32'd1;
          genDone   <= genDone + 7'd1;
          if (k == 4'(LANES - 1)) begin
            k     <= '0;
            state <= S_NEXT_BATCH;
          end else begin
            k <= k + 4'd1;
          end
        end

        S_NEXT_BATCH: begin
          if (batch == 4'(POP_SIZE / LANES - 1)) begin
            state <= S_GEN_END;
          end else begin
            batch  <= batch + 4'd1;
            g      <= '0;
            k      <= '0;
            runIdx <= '0;
            state  <= S_LOAD;
          end
        end

        S_GEN_END: begin
          // mean survival % over POP_SIZE x RUNS_TRAIN runs of T_MAX steps:
          // sum * 100 / 524,160 ~= (sum * 25) >> 17
          lastMeanSurv  <= 7'((27'(genSumT) * 27'd25) >> 17);
          lastMeanValid <= 1'b1;
          gen           <= gen + 8'd1;
          genPulse      <= 1'b1;
          holdCount     <= '0;
          state         <= S_HOLD_GEN;
        end

        S_HOLD_GEN: begin
          if (!slow || holdCount >= 8'(HOLD_GEN_FRAMES)) state <= S_GEN_START;
          else if (frameTick) holdCount <= holdCount + 8'd1;
        end

        default: state <= S_IDLE;
      endcase

      if (abort) state <= S_IDLE;
    end
  end

  assign active = (state != S_IDLE);

  always_comb begin
    stage = (state == S_IDLE) ? STG_IDLE : STG_TRAINING;
    case (state)
      S_IDLE:                  runState = RS_NONE;
      S_RUN:                   runState = RS_READY;
      S_HOLD_RUN, S_RUN_END:   runState = RS_FINISHED;
      S_STORE, S_NEXT_BATCH:   runState = RS_SCORING;
      S_GEN_END, S_HOLD_GEN:   runState = RS_NEXT_GEN;
      default:                 runState = RS_LOADING;
    endcase
  end

endmodule
