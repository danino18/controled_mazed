// Every piece of text on screen, as a table of fixed lines.
//
// A line has a position, a scale (character cell = 8 << scale pixels), the
// game screens it appears on, a colour, and a string. Some lines have dynamic
// characters: score digits, best-score digits, or a menu cursor in column 0.
// Lines never overlap on the same screen, so one font ROM serves them all.

package text_pkg;
  import palette_pkg::*, game_state_pkg::*;

  localparam int NUM_LINES = 22;
  localparam int MAX_CHARS = 32;

  // Screen masks: bit n = visible while game_fsm is in state n.
  localparam logic [5:0] SCR_MENU_DIFF = 6'b000001 << ST_MENU_DIFF;
  localparam logic [5:0] SCR_MENU_OBST = 6'b000001 << ST_MENU_OBST;
  localparam logic [5:0] SCR_READY     = 6'b000001 << ST_READY;
  localparam logic [5:0] SCR_PLAY      = 6'b000001 << ST_PLAY;
  localparam logic [5:0] SCR_HIT       = 6'b000001 << ST_HIT;
  localparam logic [5:0] SCR_OVER      = 6'b000001 << ST_GAME_OVER;
  localparam logic [5:0] SCR_MENUS     = SCR_MENU_DIFF | SCR_MENU_OBST;
  localparam logic [5:0] SCR_HUD       = SCR_READY | SCR_PLAY | SCR_HIT;

  localparam logic [2:0] KIND_STATIC   = 3'd0;
  localparam logic [2:0] KIND_SCORE    = 3'd1;   // last 3 characters = current score
  localparam logic [2:0] KIND_BEST     = 3'd2;   // last 3 characters = best score
  localparam logic [2:0] KIND_ITEM     = 3'd3;   // column 0 = '>' when item == cursor
  localparam logic [2:0] KIND_NEW_BEST = 3'd4;   // shown (blinking) only after a new best
  // KIND_SPEED intentionally not added here: line_cfg's case statement hits a
  // Quartus 17 Verific elaborator crash (confirmed empirically) at 23 entries.
  // The world-speed readout is drawn by the separate speed_readout.sv instead.

  typedef struct packed {
    logic [9:0]               x;
    logic [8:0]               y;
    logic [1:0]               scale;
    logic [5:0]               length;
    logic [5:0]               screens;
    color_t                   color;
    logic [2:0]               kind;
    logic [1:0]               item;
    logic [MAX_CHARS*8-1:0]   text;      // string literal, right-justified
  } line_t;

  function automatic line_t line_cfg(input logic [4:0] idx);
    line_t l;
    l = '0;
    case (idx)
      // -------------------------------------------------------------- both menus
      5'd0:  begin l.x = 10'd80;  l.y = 9'd40;  l.scale = 2'd2; l.length = 6'd15; l.screens = SCR_MENUS;
                   l.color = C_TEXT_GOLD;  l.text = "CONTROLLED MAZE"; end
      5'd1:  begin l.x = 10'd200; l.y = 9'd396; l.scale = 2'd1; l.length = 6'd9;  l.screens = SCR_MENUS;
                   l.color = C_TEXT_GOLD;  l.kind = KIND_BEST; l.text = "BEST  000"; end
      5'd2:  begin l.x = 10'd80;  l.y = 9'd420; l.scale = 2'd1; l.length = 6'd30; l.screens = SCR_MENUS;
                   l.color = C_TEXT_DIM;   l.text = "UP/DOWN SELECT   ENTER CONFIRM"; end
      // -------------------------------------------------------------- difficulty menu
      5'd3:  begin l.x = 10'd184; l.y = 9'd112; l.scale = 2'd1; l.length = 6'd17; l.screens = SCR_MENU_DIFF;
                   l.color = C_TEXT_CYAN;  l.text = "SELECT DIFFICULTY"; end
      5'd4:  begin l.x = 10'd240; l.y = 9'd168; l.scale = 2'd2; l.length = 6'd6;  l.screens = SCR_MENU_DIFF;
                   l.color = C_TEXT_DIM;   l.kind = KIND_ITEM; l.item = 2'd0; l.text = "* EASY"; end
      5'd5:  begin l.x = 10'd240; l.y = 9'd216; l.scale = 2'd2; l.length = 6'd8;  l.screens = SCR_MENU_DIFF;
                   l.color = C_TEXT_DIM;   l.kind = KIND_ITEM; l.item = 2'd1; l.text = "* MEDIUM"; end
      5'd6:  begin l.x = 10'd240; l.y = 9'd264; l.scale = 2'd2; l.length = 6'd6;  l.screens = SCR_MENU_DIFF;
                   l.color = C_TEXT_DIM;   l.kind = KIND_ITEM; l.item = 2'd2; l.text = "* HARD"; end
      // -------------------------------------------------------------- obstacle menu
      5'd7:  begin l.x = 10'd192; l.y = 9'd112; l.scale = 2'd1; l.length = 6'd16; l.screens = SCR_MENU_OBST;
                   l.color = C_TEXT_CYAN;  l.text = "SELECT OBSTACLES"; end
      5'd8:  begin l.x = 10'd208; l.y = 9'd168; l.scale = 2'd2; l.length = 6'd9;  l.screens = SCR_MENU_OBST;
                   l.color = C_TEXT_DIM;   l.kind = KIND_ITEM; l.item = 2'd0; l.text = "* 1 CORAL"; end
      5'd9:  begin l.x = 10'd208; l.y = 9'd216; l.scale = 2'd2; l.length = 6'd10; l.screens = SCR_MENU_OBST;
                   l.color = C_TEXT_DIM;   l.kind = KIND_ITEM; l.item = 2'd1; l.text = "* 2 CORALS"; end
      5'd10: begin l.x = 10'd208; l.y = 9'd264; l.scale = 2'd2; l.length = 6'd10; l.screens = SCR_MENU_OBST;
                   l.color = C_TEXT_DIM;   l.kind = KIND_ITEM; l.item = 2'd2; l.text = "* 3 CORALS"; end
      // -------------------------------------------------------------- in-game HUD
      5'd11: begin l.x = 10'd488; l.y = 9'd10;  l.scale = 2'd1; l.length = 6'd9;  l.screens = SCR_HUD;
                   l.color = C_TEXT_WHITE; l.kind = KIND_SCORE; l.text = "SCORE 000"; end
      5'd12: begin l.x = 10'd488; l.y = 9'd30;  l.scale = 2'd1; l.length = 6'd9;  l.screens = SCR_HUD;
                   l.color = C_TEXT_GOLD;  l.kind = KIND_BEST; l.text = "BEST  000"; end
      // -------------------------------------------------------------- get ready
      5'd13: begin l.x = 10'd192; l.y = 9'd112; l.scale = 2'd2; l.length = 6'd9;  l.screens = SCR_READY;
                   l.color = C_TEXT_GOLD;  l.text = "GET READY"; end
      5'd14: begin l.x = 10'd192; l.y = 9'd160; l.scale = 2'd1; l.length = 6'd23; l.screens = SCR_READY;
                   l.color = C_TEXT_WHITE; l.text = "UP/DOWN MOVES THE CORAL"; end
      5'd15: begin l.x = 10'd192; l.y = 9'd180; l.scale = 2'd1; l.length = 6'd24; l.screens = SCR_READY;
                   l.color = C_TEXT_CYAN;  l.text = "THE BIRD SWIMS BY ITSELF"; end
      // -------------------------------------------------------------- game over
      5'd16: begin l.x = 10'd32;  l.y = 9'd40;  l.scale = 2'd3; l.length = 6'd9;  l.screens = SCR_OVER;
                   l.color = C_TEXT_RED;   l.text = "GAME OVER"; end
      5'd17: begin l.x = 10'd176; l.y = 9'd136; l.scale = 2'd2; l.length = 6'd9;  l.screens = SCR_OVER;
                   l.color = C_TEXT_WHITE; l.kind = KIND_SCORE; l.text = "SCORE 000"; end
      5'd18: begin l.x = 10'd176; l.y = 9'd180; l.scale = 2'd2; l.length = 6'd9;  l.screens = SCR_OVER;
                   l.color = C_TEXT_GOLD;  l.kind = KIND_BEST; l.text = "BEST  000"; end
      5'd19: begin l.x = 10'd248; l.y = 9'd222; l.scale = 2'd1; l.length = 6'd9;  l.screens = SCR_OVER;
                   l.color = C_TEXT_GOLD;  l.kind = KIND_NEW_BEST; l.text = "NEW BEST!"; end
      5'd20: begin l.x = 10'd176; l.y = 9'd264; l.scale = 2'd2; l.length = 6'd9;  l.screens = SCR_OVER;
                   l.color = C_TEXT_DIM;   l.kind = KIND_ITEM; l.item = 2'd0; l.text = "* RESTART"; end
      5'd21: begin l.x = 10'd176; l.y = 9'd312; l.scale = 2'd2; l.length = 6'd11; l.screens = SCR_OVER;
                   l.color = C_TEXT_DIM;   l.kind = KIND_ITEM; l.item = 2'd1; l.text = "* MAIN MENU"; end
      default: l = '0;
    endcase
    return l;
  endfunction

endpackage
