`timescale 1ns / 1ps
module Battleship(
    input  wire        clk,
    input  wire        reset,
    input  wire        view_switch,    // SW 15 -> 0 = show P1 board, 1 = show P2 board (hardware switch)
    input  wire        confirm_switch, // SW 14 -> when toggled (rising edge) ends turn -> blackout until view_switch flips
    input  wire        btnr,           // button (T17) -> place ship
    input  wire        placing_mode,  // SW 13 -> 0 = players placing ships, 1 = players firing at ships

    // PMOD JSTK
    input  wire        MISO,
    output wire        MOSI,
    output wire        SS,
    output wire        SCLK,

    // VGA
    output wire        hsync,
    output wire        vsync,
    output wire [3:0]  red,
    output wire [3:0]  green,
    output wire [3:0]  blue,

    // DISPLAY
    output wire [6:0] seg,
    output wire [3:0] an

);

//  JOYSTICK INTERFACE (PmodJSTK) 
wire sndRec;
wire [7:0] sndData;
wire [39:0] jstkData;

PmodJSTK joystick(
    .CLK(clk),
    .RST(reset),
    .sndRec(sndRec),
    .DIN(sndData),
    .MISO(MISO),
    .SS(SS),
    .SCLK(SCLK),
    .MOSI(MOSI),
    .DOUT(jstkData)
);

assign sndData = {6'b100000, 2'b00};

ClkDiv_5Hz joyclk(
    .CLK(clk),
    .RST(reset),
    .CLKOUT(sndRec)
);

//joystick position
wire [9:0] joy_x = {jstkData[9:8],  jstkData[23:16]};
wire [9:0] joy_y = {jstkData[25:24], jstkData[39:32]};

wire joy_btn_C = jstkData[0];
wire joy_btn_Z = jstkData[2];

//  CURSOR CONTROL - getting the square from the joystick data
reg [3:0] sel_row = 4'd4;
reg [3:0] sel_col = 4'd4;

reg joy_left, joy_right, joy_up, joy_down;
always @(posedge clk) begin
    if (reset) begin
        joy_left  <= 1'b0;
        joy_right <= 1'b0;
        joy_up    <= 1'b0;
        joy_down  <= 1'b0;
    end else begin
        joy_left  <= (joy_x < 10'd350);
        joy_right <= (joy_x > 10'd650);
        joy_up    <= (joy_y < 10'd350);
        joy_down  <= (joy_y > 10'd650);
    end
end

reg [23:0] move_div;
always @(posedge clk) move_div <= move_div + 1;
wire move_tick = (move_div == 0);

always @(posedge clk) begin
    if (reset) begin
        sel_row <= 4'd4;
        sel_col <= 4'd4;
    end else if (move_tick) begin
        if (joy_left  && sel_col > 0) sel_col <= sel_col - 1;
        if (joy_right && sel_col < 8) sel_col <= sel_col + 1;
        if (joy_up    && sel_row > 0) sel_row <= sel_row - 1;
        if (joy_down  && sel_row < 8) sel_row <= sel_row + 1;
    end
end

//  BUTTON DEBOUNCING - d-flip flops
reg prev_C, prev_Z;
always @(posedge clk) begin
    if (reset) begin
        prev_C <= 1'b0; prev_Z <= 1'b0;
    end else begin
        prev_C <= joy_btn_C;
        prev_Z <= joy_btn_Z;
    end
end

wire jstk_place_pulse = joy_btn_C & ~prev_C;
wire jstk_fire_pulse  = joy_btn_Z & ~prev_Z;

reg prev_btnr;
always @(posedge clk) begin
    if (reset) prev_btnr <= 1'b0;
    else prev_btnr <= btnr;
end
wire btnr_pulse = btnr & ~prev_btnr;

wire place_pulse = jstk_place_pulse | (btnr_pulse & ~placing_mode);
wire fire_pulse  = jstk_fire_pulse  | (btnr_pulse & placing_mode);

//  USING VGA SIGNAL
wire video_on;
wire p_tick;
wire [9:0] x, y;

vga_sync vga(
    .clk(clk),
    .reset(reset),
    .hsync(hsync),
    .vsync(vsync),
    .video_on(video_on),
    .p_tick(p_tick),
    .x(x),
    .y(y)
);

//  GAME LOGIC - two 9x9 grids
reg [2:0] grid_p1 [0:8][0:8];
reg [2:0] grid_p2 [0:8][0:8];

localparam [2:0] EMPTY = 3'b00, SHIP = 3'b01, MISS = 3'b10, HIT = 3'b11, HIT_ORANGE = 3'b100;

reg hit_flag;
reg fail_flag;
reg [23:0] result_timer; // holds how long to show the result

reg [3:0] ship_placed_p1; // up to 5
reg [3:0] ship_placed_p2;
reg [4:0] ship_remaining_p1; // decremented on hits (range 0..81 but 5*1 cells here <=5)
reg [4:0] ship_remaining_p2;

reg game_over;
reg winning_player; // 1 = player1 wins, 2 = player2 wins (store as 1 or 2)
reg win_player = 0; //1 if we blackout
integer r, c;
always @(posedge clk) begin
    if (reset) begin
        hit_flag <= 1'b0;
        fail_flag <= 1'b0;
        result_timer <= 24'd0;
        ship_placed_p1 <= 4'd0;
        ship_placed_p2 <= 4'd0;
        ship_remaining_p1 <= 5'd0;
        ship_remaining_p2 <= 5'd0;
        game_over <= 1'b0;
        winning_player <= 1'b0;
        for (r = 0; r < 9; r = r + 1) begin
            for (c = 0; c < 9; c = c + 1) begin
                grid_p1[r][c] <= EMPTY;
                grid_p2[r][c] <= EMPTY;
            end
        end
    end else begin
        // decrement timer if active, clear flags when it expires
        if (result_timer != 24'd0) begin
            result_timer <= result_timer - 1;
            if (result_timer == 24'd1) begin
                hit_flag <= 1'b0;
                fail_flag <= 1'b0;
            end
        end

        // If game over, ignore gameplay
        if (!game_over) begin

            if (!placing_mode && place_pulse) begin
                if (view_switch == 1'b0) begin
                    // placing on P1 board
                    if (grid_p1[sel_row][sel_col] == EMPTY) begin
                        if (ship_placed_p1 < 4'd5) begin
                            grid_p1[sel_row][sel_col] <= SHIP;
                            ship_placed_p1 <= ship_placed_p1 + 1'b1;
                            ship_remaining_p1 <= ship_remaining_p1 + 1'b1;
                        end else begin
                            // if trying to place more than 5 -> ignore (do nothing)
                        end
                    end
                end else begin
                    // placing on P2 board
                    if (grid_p2[sel_row][sel_col] == EMPTY) begin
                        if (ship_placed_p2 < 4'd5) begin
                            grid_p2[sel_row][sel_col] <= SHIP;
                            ship_placed_p2 <= ship_placed_p2 + 1'b1;
                            ship_remaining_p2 <= ship_remaining_p2 + 1'b1;
                        end else begin
                            // ignore
                        end
                    end
                end
            end

            // -------------------- FIRING MODE (placing_mode = 1) --------------------
            // Only process a new fire if the result timer is not active (prevents re-trigger)
            if (placing_mode && fire_pulse && (result_timer == 24'd0)) begin
                if (view_switch == 1'b0) begin
                    // Player is viewing P1 board; they fire at P2
                    if (grid_p2[sel_row][sel_col] == SHIP) begin
                        grid_p2[sel_row][sel_col] <= HIT;
                        grid_p1[sel_row][sel_col] <= HIT_ORANGE;
                        hit_flag <= 1'b1;
                        result_timer <= 24'd3_000_000;
                        // decrement P2 remaining ships
                        if (ship_remaining_p2 > 0) ship_remaining_p2 <= ship_remaining_p2 - 1'b1;
                        // check for game over: if P2 has no ships left -> player viewing (P1) wins
                        if ((ship_remaining_p2 > 0) && (ship_remaining_p2 - 1'b1 == 0)) begin
                            game_over <= 1'b1;
                            win_player <= 1'b1;
                            winning_player <= 1'b1; // player 1 wins
                        end else if (ship_remaining_p2 == 0) begin
                            // end game, do nothing
                        end
                    end else if (grid_p2[sel_row][sel_col] == EMPTY) begin
                        grid_p1[sel_row][sel_col] <= MISS;
                        fail_flag <= 1'b1;
                        result_timer <= 24'd3_000_000;
                    end
                end else begin
                    // viewing P2 board; fire at P1
                    if (grid_p1[sel_row][sel_col] == SHIP) begin
                        grid_p1[sel_row][sel_col] <= HIT;
                        grid_p2[sel_row][sel_col] <= HIT_ORANGE;
                        hit_flag <= 1'b1;
                        result_timer <= 24'd3_000_000;
                        // decrement P1 remaining ships
                        if (ship_remaining_p1 > 0) ship_remaining_p1 <= ship_remaining_p1 - 1'b1;
                        if ((ship_remaining_p1 > 0) && (ship_remaining_p1 - 1'b1 == 0)) begin
                            game_over <= 1'b1;
                            win_player <= 1'b1;
                            winning_player <= 1'b0; // store 0 then display as 2 below (we'll treat 0 => player2)
                            // to be consistent set winning_player to 0 meaning player2, but we'll map later
                        end else if (ship_remaining_p1 == 0) begin
                            // end game, do nothing
                        end
                    end else if (grid_p1[sel_row][sel_col] == EMPTY) begin
                        grid_p2[sel_row][sel_col] <= MISS;
                        fail_flag <= 1'b1;
                        result_timer <= 24'd3_000_000;
                    end
                end
            end
        end // if !game_over
    end
end



//  TURN CONFIRM / BLACKOUT LOGIC (preventing cheating)
//  - confirm_switch rising edge -> awaiting_next_player = 1 (blackout)
//  - blackout remains until view_switch changes (player flips switch)
reg awaiting_next_player;
reg last_view_switch;
reg prev_confirm;

always @(posedge clk) begin
    if (reset) begin
        awaiting_next_player <= 1'b0;
        last_view_switch     <= view_switch;
        prev_confirm         <= 1'b0;
    end else begin
        prev_confirm <= confirm_switch;

        // detect rising edge of confirm_switch
        if (confirm_switch & ~prev_confirm) begin
            awaiting_next_player <= 1'b1;
            last_view_switch <= view_switch;
        end

        // if awaiting and the user changed view_switch away from last_view_switch -> resume
        if ((awaiting_next_player  && (view_switch != last_view_switch))) begin
            awaiting_next_player <= 1'b0;
            last_view_switch <= view_switch;
        end
    end
end

//  SEVEN-SEGMENT DISPLAY LOGIC 
seven_segment_display seg_display(
    .clk(clk),
    .HIT(hit_flag),
    .FAIL(fail_flag),
    .seg(seg),
    .an(an)
);

//  VGA TEXT + CURSOR
localparam integer BOARD_X = 80;
localparam integer BOARD_Y = 40;
localparam integer CELL_SIZE = 40;

wire in_board_x = (x >= BOARD_X) && (x < BOARD_X + CELL_SIZE*9);
wire in_board_y = (y >= BOARD_Y) && (y < BOARD_Y + CELL_SIZE*9);

wire [3:0] cur_col = in_board_x ? ((x - BOARD_X) / CELL_SIZE) : 4'd15;
wire [3:0] cur_row = in_board_y ? ((y - BOARD_Y) / CELL_SIZE) : 4'd15;

wire cursor_active = (cur_row == sel_row) && (cur_col == sel_col);

// choose which board to display based on view_switch
reg [2:0] show_cell_state;
always @(*) begin
    if (!video_on) show_cell_state = EMPTY;
    else if (!(in_board_x && in_board_y)) show_cell_state = EMPTY;
    else begin
        if (view_switch == 1'b0)
            show_cell_state = grid_p1[cur_row][cur_col];
        else
            show_cell_state = grid_p2[cur_row][cur_col];
    end
end

// cell local coordinates (valid only when in_board_x && in_board_y)
wire [5:0] local_x = (in_board_x && in_board_y) ? (x - (BOARD_X + cur_col*CELL_SIZE)) : 6'd0;
wire [5:0] local_y = (in_board_x && in_board_y) ? (y - (BOARD_Y + cur_row*CELL_SIZE)) : 6'd0;
wire cell_border = (local_x < 2) || (local_x >= CELL_SIZE-2) || (local_y < 2) || (local_y >= CELL_SIZE-2);

// ---------------------- TEXT "PLAYER 1"/"PLAYER 2" (bottom-left) ---------------------------
localparam integer TEXT_X = 8;
localparam integer TEXT_Y = 464;   // bottom-left corner area
localparam integer TEXT_CHARS = 8; // "PLAYER 1"

wire inside_text = (x >= TEXT_X) && (x < TEXT_X + TEXT_CHARS*8) && (y >= TEXT_Y) && (y < TEXT_Y + 8);

wire [2:0] char_x = inside_text ? ((x - TEXT_X) & 3'd7) : 3'd0; 
wire [2:0] char_y = inside_text ? ((y - TEXT_Y) & 3'd7) : 3'd0; 
wire [3:0] char_idx = inside_text ? ((x - TEXT_X) >> 3) : 4'd0; 

reg [7:0] text_string [0:TEXT_CHARS-1];
integer ti;
always @(*) begin
    text_string[0] = "P";
    text_string[1] = "L";
    text_string[2] = "A";
    text_string[3] = "Y";
    text_string[4] = "E";
    text_string[5] = "R";
    text_string[6] = " ";
    text_string[7] = view_switch ? "2" : "1";
end

wire font_pixel;
wire [7:0] current_char = text_string[char_idx];

tiny_font8x8 font_unit (
    .char_code(current_char),
    .x(char_x),
    .y(char_y),
    .pixel(font_pixel)
);

// ---------------------- CENTERED WIN TEXT (shown when game_over) ---------------------------
// We'll display "PLAYER X WINS" centered on screen when game_over == 1
localparam integer WIN_TEXT_CHARS = 13; // e.g. "PLAYER 1 WINS" is 13 chars
localparam integer WIN_TEXT_X = 320 - (WIN_TEXT_CHARS*8)/2; // center horizontally
localparam integer WIN_TEXT_Y = 220; // roughly vertical center

wire inside_win_text = (x >= WIN_TEXT_X) && (x < WIN_TEXT_X + WIN_TEXT_CHARS*8) && (y >= WIN_TEXT_Y) && (y < WIN_TEXT_Y + 8);
wire [2:0] win_char_x = inside_win_text ? ((x - WIN_TEXT_X) & 3'd7) : 3'd0;
wire [2:0] win_char_y = inside_win_text ? ((y - WIN_TEXT_Y) & 3'd7) : 3'd0;
wire [3:0] win_char_idx = inside_win_text ? ((x - WIN_TEXT_X) >> 3) : 4'd0;

reg [7:0] win_text_string [0:WIN_TEXT_CHARS-1];
integer wti;
always @(*) begin
    // default to spaces
    for (wti = 0; wti < WIN_TEXT_CHARS; wti = wti + 1) win_text_string[wti] = " ";
    // Fill "PLAYER "
    win_text_string[0]  = "P";
    win_text_string[1]  = "L";
    win_text_string[2]  = "A";
    win_text_string[3]  = "Y";
    win_text_string[4]  = "E";
    win_text_string[5]  = "R";
    win_text_string[6]  = " ";
    // player digit
    if (game_over) begin
        if (winning_player == 1'b1) win_text_string[7] = "1";
        else win_text_string[7] = "2";
    end else win_text_string[7] = " ";
    // " WINS"
    win_text_string[8]  = " ";
    win_text_string[9]  = "W";
    win_text_string[10] = "I";
    win_text_string[11] = "N";
    win_text_string[12] = "S";
end

wire win_font_pixel;
wire [7:0] win_current_char = win_text_string[win_char_idx];

tiny_font8x8 win_font_unit (
    .char_code(win_current_char),
    .x(win_char_x),
    .y(win_char_y),
    .pixel(win_font_pixel)
);

// ---------------------- FINAL COLOR OUTPUT (with blackout / win override) ------------------------------
reg [3:0] red_reg, green_reg, blue_reg;

always @(*) begin
    // If game_over, show win text overlay on top of everything (overrides blackout)
    if (game_over && inside_win_text && win_font_pixel) begin
        // bright white for win text
        red_reg   = 4'd15 >> 0;
        green_reg = 4'd15 >> 0;
        blue_reg  = 4'd15 >> 0;
    end 
    else if (game_over) begin
        red_reg   = 4'd0;
        green_reg = 4'd0;
        blue_reg  = 4'd0;
    end
    else if (awaiting_next_player) begin
        // BLACKOUT takes absolute priority (unless game_over)
        red_reg   = 4'd0;
        green_reg = 4'd0;
        blue_reg  = 4'd0;
    end else begin
        // default: background black
        red_reg = 4'd0; green_reg = 4'd0; blue_reg = 4'd0;

        // text overlay has priority (when not blacked out)
        if (inside_text && font_pixel) begin
            // white text (use mid-scale as 4-bit)
            red_reg   = 4'd15 >> 1;
            green_reg = 4'd15 >> 1;
            blue_reg  = 4'd15 >> 1;
        end
        else if (!video_on) begin
            red_reg = 4'd0; green_reg = 4'd0; blue_reg = 4'd0;
        end
        else if (!(in_board_x && in_board_y)) begin
            // background / play area: dark blue
            red_reg   = 4'd0;
            green_reg = 4'd0;
            blue_reg  = 4'd4;
        end
        else begin
            // inside board: draw cell contents or cursor highlight on top
            if (cursor_active) begin
                // cursor highlight (yellow-ish)
                red_reg = 4'd12; green_reg = 4'd12; blue_reg = 4'd0;
            end else begin
                case (show_cell_state)
                    EMPTY: begin
                        if (cell_border) begin
                            red_reg = 4'd8; green_reg = 4'd8; blue_reg = 4'd8;
                        end else begin
                            red_reg = 4'd0; green_reg = 4'd0; blue_reg = 4'd6;
                        end
                    end
                    SHIP: begin
                        if (cell_border) begin
                            red_reg = 4'd6; green_reg = 4'd6; blue_reg = 4'd6;
                        end else begin
                            red_reg = 4'd0; green_reg = 4'd10; blue_reg = 4'd0;
                        end
                    end
                    MISS: begin
                        if (cell_border) begin
                            red_reg = 4'd6; green_reg = 4'd6; blue_reg = 4'd6;
                        end else begin
                            red_reg = 4'd12; green_reg = 4'd12; blue_reg = 4'd12;
                        end
                    end
                    HIT: begin
                        if (cell_border) begin
                            red_reg = 4'd10; green_reg = 4'd3; blue_reg = 4'd3;
                        end else begin
                            red_reg = 4'd12; green_reg = 4'd0; blue_reg = 4'd0;
                        end
                    end
                    HIT_ORANGE: begin
                        if (cell_border) begin
                            red_reg = 4'd10; green_reg = 4'd3; blue_reg = 4'd3;
                        end else begin
                            red_reg = 4'd12; green_reg = 4'd6; blue_reg = 4'd0;
                        end
                    end
                    default: begin
                        red_reg = 4'd0; green_reg = 4'd0; blue_reg = 4'd0;
                    end
                endcase
            end
        end
    end
end

assign red   = red_reg;
assign green = green_reg;
assign blue  = blue_reg;

endmodule


