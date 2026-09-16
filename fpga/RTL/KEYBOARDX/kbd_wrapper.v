// Verilog-2001 wrapper for the supplied precompiled keyboard block (KBDINTF.qxp).
// KBDINTF names one output "break", which is a reserved word in SystemVerilog,
// so it can only be connected from a plain Verilog file.

module kbd_wrapper (
    input        clk,
    input        resetN,
    input        PS2_CLK,
    input        PS2_DAT,
    output [8:0] keyCode,     // {E0-extended, scan code}
    output       make,        // one-clock pulse: key pressed (repeats while held)
    output       brakk        // one-clock pulse: key released
);

  KBDINTF kbd (
      .CLOCK_50(clk),         // the supplied demo also clocks this block from the pixel clock
      .resetN  (resetN),
      .PS2_CLK (PS2_CLK),
      .PS2_DAT (PS2_DAT),
      .keyCode (keyCode),
      .make    (make),
      .break   (brakk)
  );

endmodule
