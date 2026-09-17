// Learning chart of the training screen (M11).
//
// One column per generation (2 px wide, generations 0..127), 1 px per percent:
//   dim bar      mean training survival % of the generation (its own worlds,
//                so not comparable between generations)
//   cyan point   survival % of the generation's best candidate on the fixed
//                validation worlds (comparable between generations)
//   gold line    survival % of the champion on the validation worlds (2 px)
// with axes and 50 % / 100 % guide lines. Only the first `count` generations
// (from the display snapshot) are drawn.
//
// The history memory lives here: the trainer writes one entry per generation
// {champion %, generation-top %, mean %}; the renderer reads it by column.
// Latency: 3 clocks, like every drawing layer.

module chart_draw
  import palette_pkg::*;
(
    input  logic        clk,
    input  logic        resetN,
    input  logic [10:0] pixelX,
    input  logic [10:0] pixelY,
    input  logic        enable,
    input  logic [7:0]  count,        // generations to draw (snapshot)
    input  logic        histWe,
    input  logic [6:0]  histWa,
    input  logic [20:0] histWd,       // {champion %, generation top %, mean %}
    output logic        drawingRequest,
    output color_t      RGBout
);

  localparam int X0     = 368;        // generation 0
  localparam int GENS   = 128;
  localparam int Y_ZERO = 432;        // 0 %
  localparam int Y_TOP  = 332;        // 100 %

  localparam color_t C_AXIS  = {3'd3, 3'd3, 2'd2};
  localparam color_t C_GUIDE = {3'd2, 3'd2, 2'd1};
  localparam color_t C_MEAN  = {3'd1, 3'd2, 2'd2};
  localparam color_t C_TOP   = {3'd0, 3'd7, 2'd3};
  localparam color_t C_CHAMP = {3'd7, 3'd6, 2'd0};

  // ---------------------------------------------------------------- stage 0
  int         x, y;
  logic       inCols, inRows, axis, guide;
  logic [6:0] col;

  assign x      = int'(pixelX);
  assign y      = int'(pixelY);
  assign inCols = x >= X0 && x < X0 + 2 * GENS;
  assign inRows = y >= Y_TOP && y <= Y_ZERO;
  assign col    = 7'((x - X0) >> 1);
  assign axis   = ((x == X0 - 1) && y >= Y_TOP - 1 && y <= Y_ZERO + 1) ||
                  ((y == Y_ZERO + 1) && x >= X0 - 1 && x <= X0 + 2 * GENS);
  assign guide  = inCols && (y == Y_TOP - 1 || y == (Y_TOP + Y_ZERO) / 2) && x[1:0] == 2'b00;

  logic [20:0] entry;

  altsyncram #(
      .operation_mode        ("DUAL_PORT"),
      .width_a               (21),
      .widthad_a             (7),
      .numwords_a            (GENS),
      .width_b               (21),
      .widthad_b             (7),
      .numwords_b            (GENS),
      .address_reg_b         ("CLOCK0"),
      .outdata_reg_b         ("UNREGISTERED"),
      .outdata_aclr_b        ("NONE"),
      .intended_device_family("Cyclone V"),
      .lpm_type              ("altsyncram"),
      .power_up_uninitialized("FALSE"),
      .read_during_write_mode_mixed_ports("DONT_CARE"),
      .ram_block_type        ("M10K")
  ) history (
      .clock0        (clk),
      .wren_a        (histWe),
      .address_a     (histWa),
      .data_a        (histWd),
      .address_b     (col),
      .q_b           (entry),
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
      .data_b        ({21{1'b1}}),
      .eccstatus     (),
      .q_a           (),
      .rden_a        (1'b1),
      .rden_b        (1'b1),
      .wren_b        (1'b0)
  );

  // ---------------------------------------------------------------- stage 1
  logic       valid1, plot1, axis1, guide1;
  logic [7:0] height1;          // percent this pixel stands for

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      valid1  <= 1'b0;
      plot1   <= 1'b0;
      axis1   <= 1'b0;
      guide1  <= 1'b0;
      height1 <= '0;
    end else begin
      valid1  <= enable && pixelX < 11'd640 && pixelY < 11'd480;
      plot1   <= inCols && inRows && ({1'b0, col} < count);
      axis1   <= axis;
      guide1  <= guide;
      height1 <= 8'(Y_ZERO - y);
    end
  end

  logic [6:0] mean, top, champ;
  assign mean  = entry[6:0];
  assign top   = entry[13:7];
  assign champ = entry[20:14];

  // ---------------------------------------------------------------- stage 2
  logic   valid2, hit2;
  color_t colour2;

  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      valid2  <= 1'b0;
      hit2    <= 1'b0;
      colour2 <= C_AXIS;
    end else begin
      valid2 <= valid1;
      hit2   <= 1'b1;
      if (plot1 && (height1 == {1'b0, champ} || height1 + 8'd1 == {1'b0, champ}))   colour2 <= C_CHAMP;
      else if (plot1 && (height1 == {1'b0, top} || height1 + 8'd1 == {1'b0, top}))  colour2 <= C_TOP;
      else if (plot1 && height1 < {1'b0, mean})                                     colour2 <= C_MEAN;
      else if (axis1)                                                               colour2 <= C_AXIS;
      else if (guide1)                                                              colour2 <= C_GUIDE;
      else                                                                          hit2    <= 1'b0;
    end
  end

  // ---------------------------------------------------------------- stage 3
  always_ff @(posedge clk or negedge resetN) begin
    if (!resetN) begin
      drawingRequest <= 1'b0;
      RGBout         <= TRANSPARENT;
    end else begin
      drawingRequest <= valid2 && hit2;
      RGBout         <= (valid2 && hit2) ? colour2 : TRANSPARENT;
    end
  end

endmodule
