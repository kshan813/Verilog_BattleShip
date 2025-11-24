`timescale 1ns / 1ps
// Battleship Top with joystick, VGA, bottom-left "PLAYER 1/2" text,
// btnr place button, and confirm_switch blackout / turn-handoff behavior.
module Battleship(
    input  wire        clk,
    input  wire        reset,
    input  wire        view_switch,    // 0 = show P1 board, 1 = show P2 board (hardware switch)
    input  wire        confirm_switch, // when toggled (rising edge) ends turn -> blackout until view_switch flips
    input  wire        btnr,           // Basys3 right button (T17) -> place ship

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
    output wire [3:0]  blue
);

// ============================================================================
//  JOYSTICK INTERFACE (PmodJSTK)
// ============================================================================
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

// joystick raw positions (10-bit)
wire [9:0] joy_x = {jstkData[9:8],  jstkData[23:16]};
wire [9:0] joy_y = {jstkData[25:24], jstkData[39:32]};

wire joy_btn_C = jstkData[0];
wire joy_btn_Z = jstkData[2];

// ============================================================================
//  CURSOR CONTROL (joystick -> sel_row/sel_col)
// ============================================================================
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

// ============================================================================
//  BUTTON EDGE DETECTION (joystick buttons + btnr)
// ============================================================================
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

// btnr edge detect (place)
reg prev_btnr;
always @(posedge clk) begin
    if (reset) prev_btnr <= 1'b0;
    else prev_btnr <= btnr;
end
wire btnr_pulse = btnr & ~prev_btnr;

// combined place / fire pulses
wire place_pulse = jstk_place_pulse | btnr_pulse;
wire fire_pulse  = jstk_fire_pulse;

// ============================================================================
//  VGA SIGNAL (vga_sync module expected in project)
// ============================================================================
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

// ============================================================================
//  GAME STATE: two 9x9 grids
// ============================================================================
localparam [1:0] EMPTY = 2'b00, SHIP = 2'b01, MISS = 2'b10, HIT = 2'b11;

reg [1:0] grid_p1 [0:8][0:8];
reg [1:0] grid_p2 [0:8][0:8];

reg placing_phase = 1'b1; // when 1, placing ships; when 0, firing

integer r, c;
always @(posedge clk) begin
    if (reset) begin
        for (r = 0; r < 9; r = r + 1)
            for (c = 0; c < 9; c = c + 1) begin
                grid_p1[r][c] <= EMPTY;
                grid_p2[r][c] <= EMPTY;
            end
    end else begin
        // Place ship on board selected by view_switch
        if (placing_phase && place_pulse) begin
            if (view_switch == 1'b0)
                grid_p1[sel_row][sel_col] <= SHIP;
            else
                grid_p2[sel_row][sel_col] <= SHIP;
        end

        // Fire on opponent board when not placing
        if (!placing_phase && fire_pulse) begin
            if (view_switch == 1'b0) begin
                // viewing P1 => active player is P1 -> fire at P2
                case (grid_p2[sel_row][sel_col])
                    SHIP:  grid_p2[sel_row][sel_col] <= HIT;
                    EMPTY: grid_p2[sel_row][sel_col] <= MISS;
                    default: grid_p2[sel_row][sel_col] <= grid_p2[sel_row][sel_col];
                endcase
            end else begin
                // viewing P2 => active player is P2 -> fire at P1
                case (grid_p1[sel_row][sel_col])
                    SHIP:  grid_p1[sel_row][sel_col] <= HIT;
                    EMPTY: grid_p1[sel_row][sel_col] <= MISS;
                    default: grid_p1[sel_row][sel_col] <= grid_p1[sel_row][sel_col];
                endcase
            end
        end
    end
end

// ============================================================================
//  TURN CONFIRM / BLACKOUT LOGIC
//  - confirm_switch rising edge -> awaiting_next_player = 1 (blackout)
//  - blackout remains until view_switch changes (player flips switch)
// ============================================================================
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
        if (awaiting_next_player && (view_switch != last_view_switch)) begin
            awaiting_next_player <= 1'b0;
            last_view_switch <= view_switch;
        end
    end
end

// ============================================================================
//  VGA RENDERING + TEXT + CURSOR
// ============================================================================
localparam integer BOARD_X = 80;
localparam integer BOARD_Y = 40;
localparam integer CELL_SIZE = 40;

wire in_board_x = (x >= BOARD_X) && (x < BOARD_X + CELL_SIZE*9);
wire in_board_y = (y >= BOARD_Y) && (y < BOARD_Y + CELL_SIZE*9);

wire [3:0] cur_col = in_board_x ? ((x - BOARD_X) / CELL_SIZE) : 4'd15;
wire [3:0] cur_row = in_board_y ? ((y - BOARD_Y) / CELL_SIZE) : 4'd15;

wire cursor_active = (cur_row == sel_row) && (cur_col == sel_col);

// choose which board to display based on view_switch
reg [1:0] show_cell_state;
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

wire [2:0] char_x = inside_text ? ((x - TEXT_X) & 3'd7) : 3'd0; // 0..7 inside char
wire [2:0] char_y = inside_text ? ((y - TEXT_Y) & 3'd7) : 3'd0; // 0..7 row
wire [3:0] char_idx = inside_text ? ((x - TEXT_X) >> 3) : 4'd0;  // 0..7 char index

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

// ---------------------- FINAL COLOR OUTPUT (with blackout override) ------------------------------
reg [3:0] red_reg, green_reg, blue_reg;

always @(*) begin
    // BLACKOUT takes absolute priority
    if (awaiting_next_player) begin
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


// ============================================================================
// tiny 8x8 monospace font module
// x,y are 3-bit positions inside an 8x8 glyph; outputs pixel=1 when that bit is set
// contains glyphs: P L A Y E R 1 2 and space
// ============================================================================
module tiny_font8x8(
    input  wire [7:0] char_code,
    input  wire [2:0] x,    // 0..7
    input  wire [2:0] y,    // 0..7
    output reg        pixel
);
reg [7:0] row;

always @(*) begin
    case (char_code)
        "P": begin
            case (y)
                0: row = 8'b11111000;
                1: row = 8'b10000100;
                2: row = 8'b10000100;
                3: row = 8'b11111000;
                4: row = 8'b10000000;
                5: row = 8'b10000000;
                6: row = 8'b00000000;
                7: row = 8'b00000000;
            endcase
        end
        "L": begin
            case (y)
                0: row = 8'b10000000;
                1: row = 8'b10000000;
                2: row = 8'b10000000;
                3: row = 8'b10000000;
                4: row = 8'b11111000;
                5: row = 8'b00000000;
                6: row = 8'b00000000;
                7: row = 8'b00000000;
            endcase
        end
        "A": begin
            case (y)
                0: row = 8'b01110000;
                1: row = 8'b10001000;
                2: row = 8'b11111000;
                3: row = 8'b10001000;
                4: row = 8'b10001000;
                5: row = 8'b00000000;
                6: row = 8'b00000000;
                7: row = 8'b00000000;
            endcase
        end
        "Y": begin
            case (y)
                0: row = 8'b10001000;
                1: row = 8'b01010000;
                2: row = 8'b00100000;
                3: row = 8'b00100000;
                4: row = 8'b00100000;
                5: row = 8'b00000000;
                6: row = 8'b00000000;
                7: row = 8'b00000000;
            endcase
        end
        "E": begin
            case (y)
                0: row = 8'b11111000;
                1: row = 8'b10000000;
                2: row = 8'b11110000;
                3: row = 8'b10000000;
                4: row = 8'b11111000;
                5: row = 8'b00000000;
                6: row = 8'b00000000;
                7: row = 8'b00000000;
            endcase
        end
        "R": begin
            case (y)
                0: row = 8'b11111000;
                1: row = 8'b10000100;
                2: row = 8'b11111000;
                3: row = 8'b10100000;
                4: row = 8'b10010000;
                5: row = 8'b00000000;
                6: row = 8'b00000000;
                7: row = 8'b00000000;
            endcase
        end
        "1": begin
            case (y)
                0: row = 8'b00100000;
                1: row = 8'b01100000;
                2: row = 8'b00100000;
                3: row = 8'b00100000;
                4: row = 8'b01110000;
                5: row = 8'b00000000;
                6: row = 8'b00000000;
                7: row = 8'b00000000;
            endcase
        end
        "2": begin
            case (y)
                0: row = 8'b01110000;
                1: row = 8'b10001000;
                2: row = 8'b00011000;
                3: row = 8'b00100000;
                4: row = 8'b11111000;
                5: row = 8'b00000000;
                6: row = 8'b00000000;
                7: row = 8'b00000000;
            endcase
        end
        " ": begin
            row = 8'b00000000;
        end
        default: row = 8'b00000000;
    endcase
end

always @(*) pixel = row[7 - x];

endmodule


