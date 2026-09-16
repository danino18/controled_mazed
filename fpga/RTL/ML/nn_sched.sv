// Sequencer of one network evaluation. It walks the 37 genes in order and
// tells nn_datapath what to do with each one. All datapaths driven by the same
// nn_sched (one per training lane) work in lockstep, so a single memory read
// returns gene g for every lane at once.
//
// geneAddr goes to a weight memory whose address is registered and whose
// output is not, so the gene appears on the memory output one clock after
// geneAddr. The control outputs are delayed by the same clock and therefore
// always describe the gene currently on the memory output.
//
// Per gene: the bias of a neuron loads the accumulator (and the previous
// hidden neuron's result is latched on the same clock); each weight adds
// input * weight. One clock after the last output weight, decide fires.
// An evaluation takes NN_GENES + 2 = 39 clocks from start to done.

module nn_sched
  import ml_pkg::*;
(
    input  logic                   clk,
    input  logic                   resetN,
    input  logic                   start,
    output logic [GENE_ADDR_W-1:0] geneAddr,
    output logic                   opLoad,     // acc <= bias
    output logic                   opAdd,      // acc <= acc + input * weight
    output logic [3:0]             inSel,      // 0..3 = features F0..F3, 4..9 = hidden h0..h5
    output logic                   latchH,     // h[hIdx] <= hardtanh(acc)
    output logic [2:0]             hIdx,
    output logic                   decide,     // action <= decision(acc)
    output logic                   busy
);

  localparam int OUT_NEURON = NN_HIDDEN;

  // ---------------------------------------------------------------- address side
  logic       issuing;
  logic [2:0] neuron;     // 0..5 hidden, 6 output
  logic [2:0] slot;       // 0 = bias, 1.. = weights

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      issuing  <= 1'b0;
      geneAddr <= '0;
      neuron   <= '0;
      slot     <= '0;
    end else if (start) begin
      issuing  <= 1'b1;
      geneAddr <= '0;
      neuron   <= '0;
      slot     <= '0;
    end else if (issuing) begin
      if (geneAddr == GENE_ADDR_W'(NN_GENES - 1)) issuing <= 1'b0;
      geneAddr <= geneAddr + 1'b1;
      if (neuron != 3'(OUT_NEURON) && slot == 3'(NN_INPUTS)) begin
        neuron <= neuron + 3'd1;
        slot   <= '0;
      end else begin
        slot <= slot + 3'd1;
      end
    end
  end

  // ---------------------------------------------------------------- data side (one clock later)
  logic       valid1;
  logic [2:0] neuron1, slot1;
  logic       lastOut1;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      valid1  <= 1'b0;
      neuron1 <= '0;
      slot1   <= '0;
      decide  <= 1'b0;
    end else begin
      valid1  <= issuing && !start;
      neuron1 <= neuron;
      slot1   <= slot;
      decide  <= lastOut1;
    end
  end

  assign lastOut1 = valid1 && neuron1 == 3'(OUT_NEURON) && slot1 == 3'(NN_HIDDEN);
  assign opLoad   = valid1 && slot1 == 3'd0;
  assign opAdd    = valid1 && slot1 != 3'd0;
  assign latchH   = opLoad && neuron1 != 3'd0;
  assign hIdx     = neuron1 - 3'd1;
  assign inSel    = (neuron1 == 3'(OUT_NEURON)) ? 4'd4 + 4'(slot1) - 4'd1 : 4'(slot1) - 4'd1;
  assign busy     = issuing || valid1 || decide;

endmodule
