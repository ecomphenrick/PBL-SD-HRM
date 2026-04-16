module hex7seg (
    input  wire        en,
    input  wire [3:0]  digit,
    input  wire        led_ready,
    input  wire        led_busy,
    input  wire        led_done,
    input  wire        led_error,
    output reg  [6:0]  seg0,
    output reg  [6:0]  seg1,
    output reg  [6:0]  seg2,
    output reg  [6:0]  seg3,
    output reg  [6:0]  seg4,
    output reg  [6:0]  seg5
);


    always @(*) begin
        // hex1–hex4 sempre apagados
        seg1 = 7'b1111111;
        seg2 = 7'b1111111;
        seg3 = 7'b1111111;
        seg4 = 7'b1111111;

        // --- hex0: dígito da predição ---
        if (!en) begin
            seg0 = 7'b1111111;
        end else begin
            case (digit)
                4'd0: seg0 = 7'b1000000;
                4'd1: seg0 = 7'b1111001;
                4'd2: seg0 = 7'b0100100;
                4'd3: seg0 = 7'b0110000;
                4'd4: seg0 = 7'b0011001;
                4'd5: seg0 = 7'b0010010;
                4'd6: seg0 = 7'b0000010;
                4'd7: seg0 = 7'b1111000;
                4'd8: seg0 = 7'b0000000;
                4'd9: seg0 = 7'b0010000;
                default: seg0 = 7'b1111111;
            endcase
        end

        // --- hex5: letra do estado atual ---
        if      (led_error) seg5 = 7'b0000110; // e
        else if (led_done)  seg5 = 7'b0100001; // d
        else if (led_busy)  seg5 = 7'b0000011; // b
        else if (led_ready) seg5 = 7'b0101111; // r
        else                seg5 = 7'b1111111; // apagado
    end
endmodule