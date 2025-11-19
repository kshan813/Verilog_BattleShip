`timescale 1ns / 1ps

module videoElements(
		input clk,
		input [17:0] Cells,
		input[8:0] Color,
		input Turn,

		output hsync, vsync,
		output [11:0] rgb
	);

	// Constants
	localparam hRes = 640;
	localparam vRes = 480;

	localparam hBorder = 100;
	localparam vBorder = 20; 

	localparam hLinePos1 = (vBorder) + 147;
	localparam hLinePos2 = (vRes - 20) - 147;

	localparam vLinePos1 = (hBorder) + 147;
	localparam vLinePos2 = (hRes - 100) - 147;

	localparam sqBorder = 40;
	localparam [4:0] plsBorder = 30;

	localparam lineWeight = 2;

	// Internal registers
	reg [1:0] pDisp;

	// Internal wires
	wire [9:0] hPos, vPos;
	wire p_tick;

	//wire plsBorder = 30;

        // instantiate vga_sync
        vga_sync vga_sync_unit (
            .clk(clk), .reset(reset), .hsync(hsync), 
            .vsync(vsync), .video_on(video_on), .p_tick(p_tick), 
            .x(hPos), .y(vPos));
   
        // Draw elements on screen
        always @(posedge p_tick) begin     
                // Horizontal grid
                if (hPos > (hBorder) && hPos < (hRes - hBorder) &&
                   ((vPos > hLinePos1 - lineWeight && vPos < hLinePos1 + lineWeight) || 
                   (vPos > hLinePos2 - lineWeight && vPos < hLinePos2 + lineWeight)))
                   
                    pDisp = 1;
                    
                // Vertical grid
                else if (vPos > (vBorder) && vPos < (vRes - vBorder) &&
                    ((hPos > vLinePos1 - lineWeight && hPos < vLinePos1 + lineWeight) || 
                    (hPos > vLinePos2 - lineWeight && hPos < vLinePos2 + lineWeight)))
                    
                    pDisp = 1;
                    
                //  Cell 1
                else if (
                    ((hPos > hBorder + sqBorder + (Cells[1] ? 0 : plsBorder) && hPos < vLinePos1 - sqBorder - (Cells[1] ? 0 : plsBorder) &&
                    vPos > vBorder + sqBorder && vPos < hLinePos1 - sqBorder) ||
                    (hPos > hBorder + sqBorder && hPos < vLinePos1 - sqBorder &&
                    vPos > vBorder + sqBorder + (Cells[1] ? 0 : plsBorder) && vPos < hLinePos1 - sqBorder - (Cells[1] ? 0 : plsBorder))) && 
                    Cells[0])
                    
                    pDisp = {Color[0],1'b1};
                    
                //  Cell 2
                else if (
                    ((hPos > vLinePos1 + sqBorder + (Cells[3] ? 0 : plsBorder) && hPos < vLinePos2 - sqBorder - (Cells[3] ? 0 : plsBorder) &&
                    vPos > vBorder + sqBorder && vPos < hLinePos1 - sqBorder) ||
                    (hPos > vLinePos1 + sqBorder && hPos < vLinePos2 - sqBorder &&
                    vPos > vBorder + sqBorder + (Cells[3] ? 0 : plsBorder) && vPos < hLinePos1 - sqBorder - (Cells[3] ? 0 : plsBorder))) && 
                    Cells[2])
                    
                    pDisp = {Color[1],1'b1};
                    
                //  Cell 3
                else if (
                    ((hPos > vLinePos2 + sqBorder + (Cells[5] ? 0 : plsBorder) && hPos < (hRes - hBorder) - sqBorder - (Cells[5] ? 0 : plsBorder) &&
                    vPos > vBorder + sqBorder && vPos < hLinePos1 - sqBorder) ||
                    (hPos > vLinePos2 + sqBorder && hPos < (hRes- hBorder) - sqBorder &&
                    vPos > vBorder + sqBorder + (Cells[5] ? 0 : plsBorder) && vPos < hLinePos1 - sqBorder - (Cells[5] ? 0 : plsBorder))) && 
                    Cells[4])
                    
                    pDisp = {Color[2],1'b1};                  
                    
                //  Cell 4
                else if (
                    ((hPos > hBorder + sqBorder + (Cells[7] ? 0 : plsBorder) && hPos < vLinePos1 - sqBorder - (Cells[7] ? 0 : plsBorder) &&
                    vPos > hLinePos1 + sqBorder && vPos < hLinePos2 - sqBorder) ||
                    (hPos > hBorder + sqBorder && hPos < vLinePos1 - sqBorder &&
                    vPos > hLinePos1 + sqBorder + (Cells[7] ? 0 : plsBorder) && vPos < hLinePos2 - sqBorder - (Cells[7] ? 0 : plsBorder))) && 
                    Cells[6])
                    
                    pDisp = {Color[3],1'b1};
                    
                //  Cell 5
                else if (
                    ((hPos > vLinePos1 + sqBorder + (Cells[9] ? 0 : plsBorder) && hPos < vLinePos2 - sqBorder - (Cells[9] ? 0 : plsBorder) &&
                    vPos > hLinePos1 + sqBorder && vPos < hLinePos2 - sqBorder) ||
                    (hPos > vLinePos1 + sqBorder && hPos < vLinePos2 - sqBorder &&
                    vPos > hLinePos1 + sqBorder + (Cells[9] ? 0 : plsBorder) && vPos < hLinePos2 - sqBorder - (Cells[9] ? 0 : plsBorder))) && 
                    Cells[8])
                    
                    pDisp = {Color[4],1'b1};
                    
                //  Cell 6
                else if (
                    ((hPos > vLinePos2 + sqBorder + (Cells[11] ? 0 : plsBorder) && hPos < (hRes - hBorder) - sqBorder - (Cells[11] ? 0 : plsBorder) &&
                    vPos > hLinePos1 + sqBorder && vPos < hLinePos2 - sqBorder) ||
                    (hPos > vLinePos2 + sqBorder && hPos < (hRes- hBorder) - sqBorder &&
                    vPos > hLinePos1 + sqBorder + (Cells[11] ? 0 : plsBorder) && vPos < hLinePos2 - sqBorder - (Cells[11] ? 0 : plsBorder))) && 
                    Cells[10])
                    
                    pDisp = {Color[5],1'b1};                 
                    
                 //  Cell 7
                else if (
                    ((hPos > hBorder + sqBorder + (Cells[13] ? 0 : plsBorder) && hPos < vLinePos1 - sqBorder - (Cells[13] ? 0 : plsBorder) &&
                    vPos > hLinePos2 + sqBorder && vPos < (vRes - vBorder) - sqBorder) ||
                    (hPos > hBorder + sqBorder && hPos < vLinePos1 - sqBorder &&
                    vPos > hLinePos2 + sqBorder + (Cells[13] ? 0 : plsBorder) && vPos < (vRes - vBorder) - sqBorder - (Cells[13] ? 0 : plsBorder))) && 
                    Cells[12])
                    
                    pDisp = {Color[6],1'b1};
                    
                //  Cell 8
                else if (
                    ((hPos > vLinePos1 + sqBorder + (Cells[15] ? 0 : plsBorder) && hPos < vLinePos2 - sqBorder - (Cells[15] ? 0 : plsBorder) &&
                    vPos > hLinePos2 + sqBorder && vPos < (vRes - vBorder) - sqBorder) ||
                    (hPos > vLinePos1 + sqBorder && hPos < vLinePos2 - sqBorder &&
                    vPos > hLinePos2 + sqBorder + (Cells[15] ? 0 : plsBorder) && vPos < (vRes - vBorder) - sqBorder - (Cells[15] ? 0 : plsBorder))) && 
                    Cells[14])
                    
                    pDisp = {Color[7],1'b1};
                    
                //  Cell 9
                else if (
                    ((hPos > vLinePos2 + sqBorder + (Cells[17] ? 0 : plsBorder) && hPos < (hRes - hBorder) - sqBorder - (Cells[17] ? 0 : plsBorder) &&
                    vPos > hLinePos2 + sqBorder && vPos < (vRes - vBorder) - sqBorder) ||
                    (hPos > vLinePos2 + sqBorder && hPos < (hRes- hBorder) - sqBorder &&
                    vPos > hLinePos2 + sqBorder + (Cells[17] ? 0 : plsBorder) && vPos < (vRes - vBorder) - sqBorder - (Cells[17] ? 0 : plsBorder))) && 
                    Cells[16])
                    
                    pDisp = {Color[8],1'b1};                 
                    
                // Background
                else
                    pDisp = 0;
        end
        
        // output
        assign rgb = (pDisp[0]) ? (pDisp[1] ? 'hF00 : 'hFFF) : 'h000;
endmodule