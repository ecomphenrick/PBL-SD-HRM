module hex7seg (
    input  wire        en,      // <- novo
    input  wire [3:0]  digit,
    output reg  [6:0]  seg0,
    output reg  [6:0]  seg1,
    output reg  [6:0]  seg2,
    output reg  [6:0]  seg3,
    output reg  [6:0]  seg4,
    output reg  [6:0]  seg5
);
    always @(*) begin
        seg1 = 7'b1111111;
        seg2 = 7'b1111111;
        seg3 = 7'b1111111;
        seg4 = 7'b1111111;
        seg5 = 7'b1111111;

        if (!en) begin
            seg0 = 7'b1111111; // apagado enquanto não terminar
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
    end
endmodule