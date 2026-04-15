module argmax10 #(
    parameter integer ACC_W = 32
)(
    input  wire signed [ACC_W-1:0] y0, y1, y2, y3, y4,
    input  wire signed [ACC_W-1:0] y5, y6, y7, y8, y9,
    output reg  [3:0]              pred,
    output reg  signed [ACC_W-1:0] max_val
);
    always @(*) begin
        pred    = 4'd0;
        max_val = y0;
        if (y1 > max_val) begin max_val = y1; pred = 4'd1; end
        if (y2 > max_val) begin max_val = y2; pred = 4'd2; end
        if (y3 > max_val) begin max_val = y3; pred = 4'd3; end
        if (y4 > max_val) begin max_val = y4; pred = 4'd4; end
        if (y5 > max_val) begin max_val = y5; pred = 4'd5; end
        if (y6 > max_val) begin max_val = y6; pred = 4'd6; end
        if (y7 > max_val) begin max_val = y7; pred = 4'd7; end
        if (y8 > max_val) begin max_val = y8; pred = 4'd8; end
        if (y9 > max_val) begin max_val = y9; pred = 4'd9; end
    end
endmodule