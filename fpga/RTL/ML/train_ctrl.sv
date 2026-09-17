// Training scheduler and genetic algorithm (M11).
//
//   SEED        RUN ID -> world-seed generator and GA random numbers
//   INIT_POP    64 random candidates, genes uniform in -64..63
//   generation g:
//     GEN_START   draw training worlds A_g, B_g (they change every generation,
//                 decision D3); clear the generation statistics and top-8 list
//     TRAIN       8 batches: LOAD lanes <- candidates 8b..8b+7; runs A_g, B_g;
//                 STORE fitness memory, top-8, generation best, survival sum
//     VALIDATE    lanes <- the generation's top 8 (by training fitness); runs on
//                 the fixed worlds V1..V4; the best of them is the generation
//                 top; if it beats the champion's validation score (strictly),
//                 it becomes the champion (CHAMP_COPY: population -> CHMP)
//     EVOLVE      next population: slots 0 and 1 = the top 2 by training
//                 fitness (elites); slots 2..63 = children: two tournaments of
//                 4 (training fitness of this generation only), uniform
//                 crossover of neuron blocks (probability 3/4), mutation whose
//                 rate grows with the stall (generations without a new champion)
//     COMMIT      the new population becomes current; history entry for the
//                 chart; generation + 1; stop test
//   stop (100 generations, SOLVED = champion completed all 4 validation worlds
//   and 10 generations passed without improvement, or the user's STOP):
//     TEST        the champion alone (lane 0; lanes 1..7 idle) plays the 8
//                 unseen test worlds T1..T8, once
//     WATCH_COPY  champion -> the WATCH AI memory (with the settings and
//                 results, through `commit`)
//     COMPLETE    until the user leaves the training screen
//
// Validation never feeds selection, elitism or the population; training
// fitness is never compared across generations.
//
// Memories: population A and B (their roles swap at COMMIT), fitness (FIT),
// champion (CHMP, In-System Memory Content Editor).

module train_ctrl
  import game_params_pkg::*, ml_pkg::*;
#(
    parameter int HOLD_RUN_FRAMES = 36,
    parameter int HOLD_GEN_FRAMES = 73,
    parameter int MAX_GEN         = 100,
    parameter int SOLVE_STALL     = 10
) (
    input  logic                         clk,
    input  logic                         resetN,

    input  logic                         start,         // one clock: begin training
    input  logic                         stop,          // one clock: stop and keep the champion
    input  logic                         abort,         // one clock: back to idle at once
    input  logic                         hold,          // pause (no new steps, no new stages)
    input  logic [15:0]                  runIdIn,
    input  logic                         frameTick,
    input  logic [2:0]                   simLevel,

    // simulator
    output logic                         runStart,
    output logic [15:0]                  runSeed,
    output logic [LANES-1:0]             laneEnable,
    output logic                         stageClear,
    output logic                         lanesAbort,
    input  logic                         runDone,
    input  logic [LANES-1:0][9:0]        accG,
    input  logic [LANES-1:0][15:0]       accTA,
    input  logic [LANES-1:0][14:0]       accT,
    input  logic [LANES-1:0][3:0]        accW,

    output logic                         laneWe,
    output logic [GENE_ADDR_W-1:0]       laneWa,
    output logic [LANES*8-1:0]           laneWd,

    // committed AI
    output logic                         watchWe,
    output logic [GENE_ADDR_W-1:0]       watchWa,
    output logic [7:0]                   watchWd,
    output logic                         commit,        // one clock after the last gene

    // learning history (chart)
    output logic                         histWe,
    output logic [6:0]                   histWa,
    output logic [20:0]                  histWd,

    // status
    output logic                         active,
    output logic                         complete,
    output logic [2:0]                   stage,
    output logic [2:0]                   runState,
    output logic [3:0]                   worldCode,     // 0 A, 1 B, 2..5 V1..V4, 6..13 T1..T8
    output logic [15:0]                  runId,
    output logic [7:0]                   gen,
    output logic [3:0]                   batch,
    output logic [3:0]                   runIdx,
    output logic [LANES-1:0][CAND_W-1:0] laneCand,
    output logic [FIT_W-1:0]             genBest,
    output logic [CAND_W-1:0]            genBestCand,
    output logic                         genBestValid,
    output logic [FIT_W-1:0]             prevBest,      // this generation's slot 0 (last generation's best)
    output logic                         prevBestValid,
    output logic [6:0]                   genDone,
    output logic [6:0]                   lastMeanSurv,
    output logic                         lastMeanValid,
    output logic [FIT_W-1:0]             valTop,        // last validation: best of the top 8
    output logic [3:0]                   valTopW,
    output logic [6:0]                   valTopSurv,
    output logic [CAND_W-1:0]            valTopCand,
    output logic                         valTopValid,
    output logic                         champExists,
    output logic [FIT_W-1:0]             champScore,
    output logic [3:0]                   champW,
    output logic [6:0]                   champSurv,
    output logic [7:0]                   champGen,
    output logic [CAND_W-1:0]            champCand,
    output logic [5:0]                   stall,
    output logic [1:0]                   mutLevel,
    output logic [FIT_W-1:0]             testScore,
    output logic [3:0]                   testW,
    output logic [6:0]                   testSurv,
    output logic                         testValid,
    output logic [1:0]                   doneReason,    // 0 max generations, 1 solved, 2 stopped
    output logic [31:0]                  evaluated,
    output logic                         genPulse
);

  localparam logic [1:0] ST_TRAIN = 2'd0;
  localparam logic [1:0] ST_VAL   = 2'd1;
  localparam logic [1:0] ST_TEST  = 2'd2;

  localparam logic [1:0] WHY_MAX_GEN = 2'd0;
  localparam logic [1:0] WHY_SOLVED  = 2'd1;
  localparam logic [1:0] WHY_STOPPED = 2'd2;

  typedef enum logic [4:0] {
      S_IDLE, S_SEED, S_INIT_POP, S_GEN_START, S_DRAW_B, S_DRAWN, S_LOAD, S_RUN_START,
      S_RUN, S_HOLD_RUN, S_RUN_END, S_STORE, S_NEXT_BATCH, S_VAL_STORE, S_VAL_DECIDE,
      S_CHAMP_COPY, S_EVO_ELITE, S_SELECT, S_BREED, S_COMMIT, S_HOLD_GEN, S_TEST_STORE,
      S_WATCH_COPY, S_COMPLETE
  } state_t;

  state_t     state;
  logic [1:0] runKind;       // ST_TRAIN / ST_VAL / ST_TEST
  logic       stopReq;

  // ================================================================ random numbers
  logic        seedLoad, seedDraw;
  logic [15:0] drawn;
  logic        rngStep;
  logic [31:0] rnd;

  assign seedDraw = (state == S_GEN_START) || (state == S_DRAW_B);

  world_seeds seeds (
      .clk(clk), .resetN(resetN), .load(seedLoad), .runId(runId), .draw(seedDraw), .seed(drawn));

  xorshift32 gaRng (
      .clk(clk), .resetN(resetN), .load(seedLoad), .runId(runId), .step(rngStep), .rnd(rnd));

  // ================================================================ memories
  // population A / B: {candidate, gene}; curIsA selects which one is current
  localparam int PAW = CAND_W + GENE_ADDR_W;

  logic           curIsA;
  logic           popWe, popWriteCur;
  logic [PAW-1:0] popWa, popRa;
  logic [7:0]     popWd, popQ;
  logic [1:0][7:0] popQs;        // read outputs of population A (0) and B (1)
  logic           weA, weB;

  assign weA  = popWe && (popWriteCur == curIsA);
  assign weB  = popWe && (popWriteCur != curIsA);
  assign popQ = curIsA ? popQs[0] : popQs[1];

  genvar p;
  generate
    for (p = 0; p < 2; p++) begin : pop
      altsyncram #(
          .operation_mode        ("DUAL_PORT"),
          .width_a               (8),
          .widthad_a             (PAW),
          .numwords_a            (1 << PAW),
          .width_b               (8),
          .widthad_b             (PAW),
          .numwords_b            (1 << PAW),
          .address_reg_b         ("CLOCK0"),
          .outdata_reg_b         ("UNREGISTERED"),
          .outdata_aclr_b        ("NONE"),
          .intended_device_family("Cyclone V"),
          .lpm_type              ("altsyncram"),
          .power_up_uninitialized("FALSE"),
          .read_during_write_mode_mixed_ports("DONT_CARE"),
          .ram_block_type        ("M10K")
      ) mem (
          .clock0        (clk),
          .wren_a        (p == 0 ? weA : weB),
          .address_a     (popWa),
          .data_a        (popWd),
          .address_b     (popRa),
          .q_b           (popQs[p]),
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
    end
  endgenerate

  // fitness of this generation's candidates
  logic              fitWe;
  logic [CAND_W-1:0] fitWa, fitRa;
  logic [FIT_W-1:0]  fitWd, fitQ;

  // champion genes (single port: In-System Memory Content Editor name CHMP)
  logic                   chmpWe;
  logic [GENE_ADDR_W-1:0] chmpA;
  logic [7:0]             chmpWd, chmpQ;

  // ================================================================ top 8 of the generation (training fitness)
  logic                   topClear, topInsert;
  logic [FIT_W-1:0]       topScore;
  logic [CAND_W-1:0]      topId;
  logic [7:0][FIT_W-1:0]  topScores;
  logic [7:0][CAND_W-1:0] topIds;
  logic [7:0]             topValid;

  top8_list top8 (
      .clk(clk), .resetN(resetN), .clear(topClear), .insert(topInsert),
      .score(topScore), .id(topId), .scores(topScores), .ids(topIds), .valid(topValid));

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
      .address_b     (fitRa),
      .q_b           (fitQ),
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

  altsyncram #(
      .operation_mode               ("SINGLE_PORT"),
      .width_a                      (8),
      .widthad_a                    (GENE_ADDR_W),
      .numwords_a                   (1 << GENE_ADDR_W),
      .intended_device_family       ("Cyclone V"),
      .lpm_hint                     ("ENABLE_RUNTIME_MOD=YES,INSTANCE_NAME=CHMP"),
      .lpm_type                     ("altsyncram"),
      .outdata_aclr_a               ("NONE"),
      .outdata_reg_a                ("UNREGISTERED"),
      .power_up_uninitialized       ("FALSE"),
      .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
      .ram_block_type               ("M10K")
  ) champion (
      .address_a     (chmpA),
      .clock0        (clk),
      .data_a        (chmpWd),
      .wren_a        (chmpWe),
      .q_a           (chmpQ),
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

  // ================================================================ helpers
  function automatic logic [3:0] runs_of(input logic [1:0] kind);
    case (kind)
      ST_TRAIN: return 4'(RUNS_TRAIN);
      ST_VAL:   return 4'd4;
      default:  return 4'd8;
    endcase
  endfunction

  // neuron block of gene g: hidden j = genes 5j..5j+4, output = genes 30..36
  function automatic logic [2:0] block_of(input logic [5:0] gi);
    if (gi >= 6'd30) return 3'd6;
    if (gi >= 6'd25) return 3'd5;
    if (gi >= 6'd20) return 3'd4;
    if (gi >= 6'd15) return 3'd3;
    if (gi >= 6'd10) return 3'd2;
    if (gi >= 6'd5)  return 3'd1;
    return 3'd0;
  endfunction

  // mutation of one gene from one random word:
  //   r[3:0] (or fewer bits) = 0     the gene mutates (1/16, 1/8, 1/4 by level)
  //   r[7:5] = 0                     a fresh random gene -64..63 (r[22:16])
  //   otherwise                      gene + (r[11:8] - r[15:12]) << level, saturated
  function automatic logic [7:0] mutate(input logic [7:0] gene, input logic [31:0] r, input logic [1:0] level);
    logic hit;
    int   d, v;
    case (level)
      2'd0:    hit = (r[3:0] == 4'd0);
      2'd1:    hit = (r[2:0] == 3'd0);
      default: hit = (r[1:0] == 2'd0);
    endcase
    if (!hit) return gene;
    if (r[7:5] == 3'd0) return 8'(int'(r[22:16]) - 64);
    d = (int'(r[11:8]) - int'(r[15:12])) <<< level;
    v = int'($signed(gene)) + d;
    if (v > 127)  v = 127;
    if (v < -128) v = -128;
    return 8'(v);
  endfunction

  function automatic logic [6:0] survival(input logic [14:0] t, input logic [3:0] w, input logic [1:0] kind);
    logic [19:0] s;
    s = 20'(t) * 20'd25;
    case (kind)
      ST_TRAIN: return (w == 4'd2) ? 7'd100 : 7'(s >> 11);
      ST_VAL:   return (w == 4'd4) ? 7'd100 : 7'(s >> 12);
      default:  return (w == 4'd8) ? 7'd100 : 7'(s >> 13);
    endcase
  endfunction

  // ================================================================ scheduler
  logic [5:0]                   g;
  logic [3:0]                   k;
  logic                         cp;
  logic [6:0]                   child;
  logic [2:0]                   tsel;
  logic                         tour;
  logic [3:0][CAND_W-1:0]       tids;
  logic [CAND_W-1:0]            tBest, parA, parB;
  logic [FIT_W-1:0]             tBestFit;
  logic                         doX;
  logic [6:0]                   xmask;
  logic                         eliteIdx;
  logic [LANES*8-1:0]           word;
  logic [7:0]                   holdCount;
  logic [15:0]                  seedA, seedB;
  logic [21:0]                  genSumT;
  logic [6:0]                   genMean;
  logic [LANES-1:0][CAND_W-1:0] loadCand;
  logic                         slow;
  logic [FIT_W-1:0]             laneFit;
  logic [CAND_W-1:0]            breedSrc;
  logic [FIT_W-1:0]             laneVal;

  assign slow     = (simLevel <= 3'd3);
  assign laneFit  = {accG[k[2:0]], accTA[k[2:0]]};
  assign laneVal  = laneFit;
  assign breedSrc = (doX && xmask[block_of(g)]) ? parB : parA;

  always_comb begin
    for (int i = 0; i < LANES; i++) begin
      case (runKind)
        ST_VAL:  loadCand[i] = topIds[i];
        ST_TEST: loadCand[i] = (i == 0) ? champCand : '0;
        default: loadCand[i] = CAND_W'({batch[2:0], 3'(i)});
      endcase
    end
  end

  // ---- memory addressing
  always_comb begin
    popRa       = '0;
    popWe       = 1'b0;
    popWriteCur = 1'b0;
    popWa       = '0;
    popWd       = '0;
    chmpA       = g;
    chmpWe      = 1'b0;
    chmpWd      = popQ;
    fitRa       = '0;
    case (state)
      S_INIT_POP: begin
        popWe       = 1'b1;
        popWriteCur = 1'b1;
        popWa       = {child[CAND_W-1:0], g};
        popWd       = 8'(int'(rnd[6:0]) - 64);
      end
      S_LOAD:       popRa = {loadCand[k[2:0]], g};
      S_CHAMP_COPY: begin
        popRa  = {valTopCand, g};
        chmpWe = cp;
      end
      S_EVO_ELITE: begin
        popRa = {topIds[{2'b00, eliteIdx}], g};
        popWe = cp;
        popWa = {5'd0, eliteIdx, g};
        popWd = popQ;
      end
      S_BREED: begin
        popRa = {breedSrc, g};
        popWe = cp;
        popWa = {child[CAND_W-1:0], g};
        popWd = mutate(popQ, rnd, mutLevel);
      end
      S_SELECT: fitRa = (tsel == 3'd0) ? rnd[5:0] : tids[tsel[1:0]];
      default: ;
    endcase
  end

  assign rngStep = (state == S_INIT_POP) || (state == S_BREED && cp) ||
                   (state == S_SELECT && (tsel == 3'd0 || (tsel == 3'd4 && tour)));

  assign laneWe = (state == S_LOAD) && (k == 4'd9);
  assign laneWa = g;
  assign laneWd = word;

  assign fitWe     = (state == S_STORE);
  assign fitWa     = laneCand[k[2:0]];
  assign fitWd     = laneFit;
  assign topInsert = (state == S_STORE);
  assign topScore  = laneFit;
  assign topId     = laneCand[k[2:0]];
  assign topClear  = (state == S_GEN_START);

  assign watchWe = (state == S_WATCH_COPY) && cp;
  assign watchWa = g;
  assign watchWd = chmpQ;

  assign histWe = (state == S_COMMIT);
  assign histWa = gen[6:0];
  assign histWd = {champSurv, valTopSurv, genMean};

  // tournament: the best of the four read so far (the first on ties)
  logic [CAND_W-1:0] tWinner;
  assign tWinner = (fitQ > tBestFit) ? tids[3] : tBest;

  always_ff @(posedge clk or negedge resetN) begin : scheduler
    logic goTest;     // start the final test (champion alone on lane 0)
    if (!resetN) begin
      state         <= S_IDLE;
      runKind       <= ST_TRAIN;
      stopReq       <= 1'b0;
      seedLoad      <= 1'b0;
      runStart      <= 1'b0;
      runSeed       <= '0;
      laneEnable    <= '0;
      stageClear    <= 1'b0;
      lanesAbort    <= 1'b0;
      commit        <= 1'b0;
      curIsA        <= 1'b1;
      runId         <= '0;
      gen           <= '0;
      batch         <= '0;
      runIdx        <= '0;
      laneCand      <= '0;
      genBest       <= '0;
      genBestCand   <= '0;
      genBestValid  <= 1'b0;
      prevBest      <= '0;
      prevBestValid <= 1'b0;
      genDone       <= '0;
      genSumT       <= '0;
      genMean       <= '0;
      lastMeanSurv  <= '0;
      lastMeanValid <= 1'b0;
      valTop        <= '0;
      valTopW       <= '0;
      valTopSurv    <= '0;
      valTopCand    <= '0;
      valTopValid   <= 1'b0;
      champExists   <= 1'b0;
      champScore    <= '0;
      champW        <= '0;
      champSurv     <= '0;
      champGen      <= '0;
      champCand     <= '0;
      stall         <= '0;
      mutLevel      <= '0;
      testScore     <= '0;
      testW         <= '0;
      testSurv      <= '0;
      testValid     <= 1'b0;
      doneReason    <= WHY_MAX_GEN;
      evaluated     <= '0;
      genPulse      <= 1'b0;
      seedA         <= '0;
      seedB         <= '0;
      g             <= '0;
      k             <= '0;
      cp            <= 1'b0;
      child         <= '0;
      tsel          <= '0;
      tour          <= 1'b0;
      tids          <= '0;
      tBest         <= '0;
      tBestFit      <= '0;
      parA          <= '0;
      parB          <= '0;
      doX           <= 1'b0;
      xmask         <= '0;
      eliteIdx      <= 1'b0;
      word          <= '0;
      holdCount     <= '0;
    end else begin
      seedLoad   <= 1'b0;
      runStart   <= 1'b0;
      stageClear <= 1'b0;
      lanesAbort <= 1'b0;
      commit     <= 1'b0;
      genPulse   <= 1'b0;
      goTest     = 1'b0;

      if (stop && state != S_IDLE && state != S_COMPLETE && state != S_WATCH_COPY) stopReq <= 1'b1;

      case (state)
        S_IDLE: begin
          if (start) begin
            runId         <= runIdIn;
            seedLoad      <= 1'b1;
            gen           <= '0;
            stall         <= '0;
            mutLevel      <= '0;
            champExists   <= 1'b0;
            valTopValid   <= 1'b0;
            testValid     <= 1'b0;
            lastMeanValid <= 1'b0;
            evaluated     <= '0;
            stopReq       <= 1'b0;
            state         <= S_SEED;
          end
        end

        S_SEED: begin                     // the generators take the RUN ID on this clock
          child <= '0;
          g     <= '0;
          state <= S_INIT_POP;
        end

        S_INIT_POP: begin                 // one random gene per clock into the current population
          if (g == 6'(NN_GENES - 1)) begin
            g <= '0;
            if (child == 7'(POP_SIZE - 1)) state <= S_GEN_START;
            else                           child <= child + 7'd1;
          end else begin
            g <= g + 6'd1;
          end
        end

        S_GEN_START: begin                // A is drawn on this clock
          batch         <= '0;
          runKind       <= ST_TRAIN;
          genBest       <= '0;
          genBestValid  <= 1'b0;
          prevBestValid <= 1'b0;
          genSumT       <= '0;
          genDone       <= '0;
          state         <= S_DRAW_B;
        end

        S_DRAW_B: begin                   // B is drawn on this clock
          seedA <= drawn;
          state <= S_DRAWN;
        end

        S_DRAWN: begin
          seedB  <= drawn;
          g      <= '0;
          k      <= '0;
          runIdx <= '0;
          state  <= S_LOAD;
        end

        // gene g of lanes 0..7: address k = 0..7, capture k = 1..8, write at k = 9
        S_LOAD: begin
          if (stopReq && runKind != ST_TEST) begin
            if (champExists) begin
              doneReason <= WHY_STOPPED;
              goTest = 1'b1;
            end else begin
              state <= S_IDLE;
            end
          end else begin
            if (k >= 4'd1 && k <= 4'd8)
              word[(int'(k) - 1) * 8 +: 8] <= (runKind == ST_TEST) ? ((k == 4'd1) ? chmpQ : 8'h00) : popQ;
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
        end

        S_RUN_START: begin
          runStart   <= 1'b1;
          laneEnable <= (runKind == ST_TEST) ? LANES'(1) : '1;
          case (runKind)
            ST_TRAIN: runSeed <= (runIdx == 4'd0) ? seedA : seedB;
            ST_VAL:   runSeed <= FIXED_SEEDS[16 * int'(runIdx) +: 16];
            default:  runSeed <= FIXED_SEEDS[16 * (4 + int'(runIdx)) +: 16];
          endcase
          if (runIdx == 4'd0) begin
            stageClear <= 1'b1;
            laneCand   <= loadCand;
          end
          state <= S_RUN;
        end

        S_RUN: begin
          if (stopReq) begin
            lanesAbort <= 1'b1;
            if (runKind == ST_TEST) begin            // a second STOP skips the final test
              stopReq   <= 1'b0;
              testValid <= 1'b0;
              g         <= '0;
              cp        <= 1'b0;
              state     <= S_WATCH_COPY;
            end else if (champExists) begin
              doneReason <= WHY_STOPPED;
              goTest = 1'b1;
            end else begin
              state <= S_IDLE;
            end
          end else if (runDone) begin
            holdCount <= '0;
            state     <= S_HOLD_RUN;
          end
        end

        S_HOLD_RUN: begin
          if (stopReq) begin
            state <= S_RUN;                          // handled there (the lanes are already idle)
          end else if (!hold && (!slow || holdCount >= 8'(HOLD_RUN_FRAMES))) begin
            state <= S_RUN_END;
          end else if (frameTick && holdCount != 8'hFF) begin
            holdCount <= holdCount + 8'd1;
          end
        end

        S_RUN_END: begin
          k <= '0;
          if (runIdx != runs_of(runKind) - 4'd1) begin
            runIdx <= runIdx + 4'd1;
            state  <= S_RUN_START;
          end else begin
            case (runKind)
              ST_TRAIN: state <= S_STORE;
              ST_VAL:   state <= S_VAL_STORE;
              default:  state <= S_TEST_STORE;
            endcase
          end
        end

        // ---------------------------------------------------------------- training results
        S_STORE: begin
          genSumT   <= genSumT + 22'(accT[k[2:0]]);
          evaluated <= evaluated + 32'd1;
          genDone   <= genDone + 7'd1;
          if (!genBestValid || laneFit > genBest) begin
            genBest      <= laneFit;
            genBestCand  <= laneCand[k[2:0]];
            genBestValid <= 1'b1;
          end
          if (batch == 4'd0 && k == 4'd0 && gen != 8'd0) begin
            prevBest      <= laneFit;
            prevBestValid <= 1'b1;
          end
          if (k == 4'(LANES - 1)) state <= S_NEXT_BATCH;
          else                    k <= k + 4'd1;
        end

        S_NEXT_BATCH: begin
          g      <= '0;
          k      <= '0;
          runIdx <= '0;
          if (batch == 4'(POP_SIZE / LANES - 1)) begin
            // mean survival % of POP_SIZE x 2 runs: sum * 100 / 524,160 ~= (sum * 25) >> 17
            genMean <= 7'((27'(genSumT) * 27'd25) >> 17);
            runKind <= ST_VAL;
          end else begin
            batch <= batch + 4'd1;
          end
          state <= S_LOAD;
        end

        // ---------------------------------------------------------------- validation
        S_VAL_STORE: begin
          if (k == 4'd0 || laneVal > valTop) begin
            valTop     <= laneVal;
            valTopW    <= accW[k[2:0]];
            valTopSurv <= survival(accT[k[2:0]], accW[k[2:0]], ST_VAL);
            valTopCand <= laneCand[k[2:0]];
          end
          if (k == 4'(LANES - 1)) begin
            valTopValid <= 1'b1;
            state       <= S_VAL_DECIDE;
          end else begin
            k <= k + 4'd1;
          end
        end

        S_VAL_DECIDE: begin
          g  <= '0;
          cp <= 1'b0;
          if (!champExists || valTop > champScore) begin
            champExists <= 1'b1;
            champScore  <= valTop;
            champW      <= valTopW;
            champSurv   <= valTopSurv;
            champGen    <= gen;
            champCand   <= valTopCand;
            stall       <= '0;
            state       <= S_CHAMP_COPY;
          end else begin
            if (stall != 6'h3F) stall <= stall + 6'd1;
            eliteIdx <= 1'b0;
            state    <= S_EVO_ELITE;
          end
        end

        S_CHAMP_COPY: begin               // gene g: read (cp = 0), write (cp = 1)
          cp <= !cp;
          if (cp) begin
            if (g == 6'(NN_GENES - 1)) begin
              g        <= '0;
              eliteIdx <= 1'b0;
              state    <= S_EVO_ELITE;
            end else begin
              g <= g + 6'd1;
            end
          end
        end

        // ---------------------------------------------------------------- evolution
        S_EVO_ELITE: begin                // next[0] <- best, next[1] <- second best
          cp <= !cp;
          if (cp) begin
            if (g == 6'(NN_GENES - 1)) begin
              g <= '0;
              if (eliteIdx) begin
                child <= 7'd2;
                tour  <= 1'b0;
                tsel  <= '0;
                state <= S_SELECT;
              end else begin
                eliteIdx <= 1'b1;
              end
            end else begin
              g <= g + 6'd1;
            end
          end
        end

        S_SELECT: begin                   // two tournaments of four (training fitness)
          case (tsel)
            3'd0: begin
              tids <= {rnd[23:18], rnd[17:12], rnd[11:6], rnd[5:0]};
              tsel <= 3'd1;
            end
            3'd1: begin
              tBest    <= tids[0];
              tBestFit <= fitQ;
              tsel     <= 3'd2;
            end
            3'd2, 3'd3: begin
              if (fitQ > tBestFit) begin
                tBest    <= tids[tsel[1:0] - 2'd1];
                tBestFit <= fitQ;
              end
              tsel <= tsel + 3'd1;
            end
            default: begin
              tsel <= '0;
              if (!tour) begin
                parA <= tWinner;
                tour <= 1'b1;
              end else begin
                parB  <= tWinner;
                tour  <= 1'b0;
                doX   <= (rnd[1:0] != 2'd0);
                xmask <= rnd[8:2];
                g     <= '0;
                cp    <= 1'b0;
                state <= S_BREED;
              end
            end
          endcase
        end

        S_BREED: begin                    // gene g: read the parent (cp = 0), write the child (cp = 1)
          cp <= !cp;
          if (cp) begin
            if (g == 6'(NN_GENES - 1)) begin
              g <= '0;
              if (child == 7'(POP_SIZE - 1)) begin
                state <= S_COMMIT;
              end else begin
                child <= child + 7'd1;
                state <= S_SELECT;
              end
            end else begin
              g <= g + 6'd1;
            end
          end
        end

        S_COMMIT: begin
          curIsA        <= !curIsA;
          gen           <= gen + 8'd1;
          genPulse      <= 1'b1;
          lastMeanSurv  <= genMean;
          lastMeanValid <= 1'b1;
          mutLevel      <= (stall >= 6'd16) ? 2'd2 : (stall >= 6'd8) ? 2'd1 : 2'd0;
          holdCount     <= '0;
          if (stopReq) begin
            doneReason <= WHY_STOPPED;
            goTest = 1'b1;
          end else if (int'(gen) + 1 >= MAX_GEN) begin
            doneReason <= WHY_MAX_GEN;
            goTest = 1'b1;
          end else if (champW == 4'd4 && int'(stall) >= SOLVE_STALL) begin
            doneReason <= WHY_SOLVED;
            goTest = 1'b1;
          end else begin
            state <= S_HOLD_GEN;
          end
        end

        S_HOLD_GEN: begin
          if (stopReq) begin
            doneReason <= WHY_STOPPED;
            goTest = 1'b1;
          end else if (!hold && (!slow || holdCount >= 8'(HOLD_GEN_FRAMES))) begin
            state <= S_GEN_START;
          end else if (frameTick && holdCount != 8'hFF) begin
            holdCount <= holdCount + 8'd1;
          end
        end

        // ---------------------------------------------------------------- final test and commit
        S_TEST_STORE: begin
          testScore <= {accG[0], accTA[0]};
          testW     <= accW[0];
          testSurv  <= survival(accT[0], accW[0], ST_TEST);
          testValid <= 1'b1;
          g         <= '0;
          cp        <= 1'b0;
          state     <= S_WATCH_COPY;
        end

        S_WATCH_COPY: begin               // champion -> WATCH memory: read (cp = 0), write (cp = 1)
          cp <= !cp;
          if (cp) begin
            if (g == 6'(NN_GENES - 1)) begin
              g      <= '0;
              commit <= 1'b1;
              state  <= S_COMPLETE;
            end else begin
              g <= g + 6'd1;
            end
          end
        end

        S_COMPLETE: ;                     // until the user leaves (abort)

        default: state <= S_IDLE;
      endcase

      if (goTest) begin
        runKind <= ST_TEST;
        stopReq <= 1'b0;
        runIdx  <= '0;
        g       <= '0;
        k       <= '0;
        state   <= S_LOAD;
      end

      if (abort) begin
        state      <= S_IDLE;
        lanesAbort <= 1'b1;
        stopReq    <= 1'b0;
        runStart   <= 1'b0;
      end
    end
  end

  // ================================================================ status
  assign active   = (state != S_IDLE);
  assign complete = (state == S_COMPLETE);

  always_comb begin
    case (state)
      S_IDLE:                                        stage = STG_IDLE;
      S_WATCH_COPY, S_COMPLETE:                      stage = STG_COMPLETE;
      S_TEST_STORE:                                  stage = STG_TESTING;
      S_VAL_STORE, S_VAL_DECIDE, S_CHAMP_COPY:       stage = STG_VALIDATE;
      S_EVO_ELITE, S_SELECT, S_BREED, S_COMMIT,
      S_HOLD_GEN:                                    stage = STG_EVOLVING;
      S_LOAD, S_RUN_START, S_RUN, S_HOLD_RUN, S_RUN_END:
        stage = (runKind == ST_VAL) ? STG_VALIDATE : (runKind == ST_TEST) ? STG_TESTING : STG_TRAINING;
      default:                                       stage = STG_TRAINING;
    endcase

    case (state)
      S_IDLE, S_WATCH_COPY, S_COMPLETE:              runState = RS_NONE;
      S_RUN:                                         runState = hold ? RS_PAUSED : RS_READY;
      S_HOLD_RUN, S_RUN_END:                         runState = hold ? RS_PAUSED : RS_FINISHED;
      S_STORE, S_NEXT_BATCH, S_VAL_STORE, S_VAL_DECIDE,
      S_CHAMP_COPY, S_TEST_STORE:                    runState = RS_SCORING;
      S_EVO_ELITE, S_SELECT, S_BREED, S_COMMIT:      runState = RS_NEXT_GEN;
      S_HOLD_GEN:                                    runState = hold ? RS_PAUSED : RS_NEXT_GEN;
      default:                                       runState = RS_LOADING;
    endcase

    case (runKind)
      ST_TRAIN: worldCode = runIdx;
      ST_VAL:   worldCode = 4'd2 + runIdx;
      default:  worldCode = 4'd6 + runIdx;
    endcase
  end

endmodule
