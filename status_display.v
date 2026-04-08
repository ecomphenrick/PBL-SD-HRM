module status_display (
    input busy,
    input done,
    input error,
    output reg [6:0] hex_out
);

    parameter CHAR_b = 7'b0000011; 
    parameter CHAR_d = 7'b0100001; 
    parameter CHAR_E = 7'b0000110;
    parameter CHAR_OFF = 7'b1111111;

    always @(*) begin
        if (error)      hex_out = CHAR_E;
        else if (busy)  hex_out = CHAR_b;
        else if (done)  hex_out = CHAR_d;
        else            hex_out = CHAR_OFF; // Apagado quando em IDLE
    end

endmodule