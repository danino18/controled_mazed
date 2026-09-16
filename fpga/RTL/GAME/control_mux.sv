// Selects who steers the maze: the keyboard, or (in the ML phase) the AI.
// The game only sees ctrlUp / ctrlDown and never knows which source drove them.

module control_mux (
    input  logic aiMode,     // 0 = human keyboard, 1 = AI
    input  logic kbdUp,
    input  logic kbdDown,
    input  logic aiUp,
    input  logic aiDown,
    input  logic aiValid,    // AI command is meaningful this frame
    output logic ctrlUp,
    output logic ctrlDown
);

  assign ctrlUp   = aiMode ? (aiValid && aiUp)   : kbdUp;
  assign ctrlDown = aiMode ? (aiValid && aiDown) : kbdDown;

endmodule
