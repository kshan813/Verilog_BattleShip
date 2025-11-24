// ==========================================================
// JoystickToGrid
// Converts JSTK X/Y values into grid cursor movement (0..8)
// ==========================================================
module JoystickToGrid #(
    parameter MAX_INDEX = 4'd8,
    parameter MIN_INDEX = 4'd0,
    parameter DEADZONE  = 10'd150   // adjust based on your joystick
)(
    input  wire        clk,
    input  wire        reset,

    // Raw joystick packet from PmodJSTK:
    // 40-bit: [39:32]=Y[7:0], [31:24]=X[1:0], [23:16]=X[7:0], ...
    input  wire [39:0] jstkData,

    output reg  [3:0]  sel_row,
    output reg  [3:0]  sel_col
);

    // Extract full 10-bit values for X/Y
    wire [9:0] joy_x = { jstkData[9:8],  jstkData[23:16] };
    wire [9:0] joy_y = { jstkData[25:24], jstkData[39:32] };

    // Direction decode based on deadzone
    wire joy_left  = (joy_x < (10'd512 - DEADZONE));
    wire joy_right = (joy_x > (10'd512 + DEADZONE));
    wire joy_up    = (joy_y > (10'd512 + DEADZONE));
    wire joy_down  = (joy_y < (10'd512 - DEADZONE));

    // Movement delay (so it steps once every N cycles)
    reg [19:0] move_delay;
    wire allow_move = (move_delay == 0);

    always @(posedge clk) begin
        if (reset) begin
            sel_row <= 0;
            sel_col <= 0;
            move_delay <= 0;
        end else begin

            // countdown
            if (move_delay != 0)
                move_delay <= move_delay - 1;

            if (allow_move) begin
                // Horizontal
                if (joy_left  && sel_col > MIN_INDEX) sel_col <= sel_col - 1;
                if (joy_right && sel_col < MAX_INDEX) sel_col <= sel_col + 1;

                // Vertical  (note: up means decreasing row)
                if (joy_up   && sel_row > MIN_INDEX) sel_row <= sel_row - 1;
                if (joy_down && sel_row < MAX_INDEX) sel_row <= sel_row + 1;

                // reload movement delay for ~80ms feel
                if (joy_left || joy_right || joy_up || joy_down)
                    move_delay <= 20'd1_800_000;  // adjust for your clock freq (100MHz)
            end
        end
    end
endmodule


