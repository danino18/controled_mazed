// Game screens (states of game_fsm) and difficulty codes, shared by the game
// logic, the text renderer and (later) the ML subsystem.

package game_state_pkg;

  localparam logic [2:0] ST_MENU_DIFF = 3'd0;   // choose EASY / MEDIUM / HARD
  localparam logic [2:0] ST_MENU_OBST = 3'd1;   // choose 1 / 2 / 3 coral columns
  localparam logic [2:0] ST_READY     = 3'd2;   // "GET READY", world frozen
  localparam logic [2:0] ST_PLAY      = 3'd3;
  localparam logic [2:0] ST_HIT       = 3'd4;   // short freeze after a collision
  localparam logic [2:0] ST_GAME_OVER = 3'd5;

  localparam logic [1:0] DIFF_EASY    = 2'd0;
  localparam logic [1:0] DIFF_MEDIUM  = 2'd1;
  localparam logic [1:0] DIFF_HARD    = 2'd2;

endpackage
