module mac_q412 #(
    parameter integer DATA_W = 16,
    parameter integer ACC_W  = 32,
    parameter integer Q_FRAC = 12
)(
    input  wire signed [DATA_W-1:0] a,
    input  wire signed [DATA_W-1:0] b,
    output wire signed [ACC_W-1:0]  product_full,
    output wire signed [ACC_W-1:0]  product_scaled
);
    assign product_full   = $signed(a) * $signed(b);
    assign product_scaled = product_full >>> Q_FRAC;
endmodule