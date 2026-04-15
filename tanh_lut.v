module tanh_lut #(
    parameter integer DATA_W = 16,
    parameter integer Q_FRAC = 12
)(
    input  wire signed [DATA_W-1:0] x_in,
    output reg  signed [DATA_W-1:0] y_out
);
    // Pontos de controle em Q4.12
    localparam signed [15:0] X0 = 16'sd0;
    localparam signed [15:0] X1 = 16'sd2048;
    localparam signed [15:0] X2 = 16'sd4096;
    localparam signed [15:0] X3 = 16'sd6144;
    localparam signed [15:0] X4 = 16'sd8192;
    localparam signed [15:0] X5 = 16'sd12288;

    localparam signed [15:0] Y0 = 16'sd0;
    localparam signed [15:0] Y1 = 16'sd1893;
    localparam signed [15:0] Y2 = 16'sd3122;
    localparam signed [15:0] Y3 = 16'sd3708;
    localparam signed [15:0] Y4 = 16'sd3949;

    localparam signed [15:0] S01 = 16'sd3786;
    localparam signed [15:0] S12 = 16'sd2460;
    localparam signed [15:0] S23 = 16'sd1172;
    localparam signed [15:0] S34 = 16'sd483;
    localparam signed [15:0] S45 = 16'sd128;

    localparam signed [15:0] SAT_POS =  16'sd4095;
    localparam signed [15:0] SAT_NEG = -16'sd4095;

    reg          sign_neg;
    reg [16:0]   x_abs_u;
    reg [15:0]   x0_seg_u;
    reg signed [15:0] y0_seg;
    reg signed [15:0] slope_seg;
    reg signed [31:0] delta_x32;
    reg signed [31:0] interp_full;
    reg signed [15:0] y_abs;
    reg signed [15:0] y_raw;  // FIX: variável intermediária antes da saturação final

    always @(*) begin
        // --- Sinal e valor absoluto ---
        sign_neg = x_in[DATA_W-1];
        if (sign_neg)
            x_abs_u = {1'b0, (~x_in + 16'd1)};
        else
            x_abs_u = {1'b0, x_in};

        // --- Defaults ---
        x0_seg_u    = X0[15:0];
        y0_seg      = Y0;
        slope_seg   = S01;
        delta_x32   = 32'sd0;
        interp_full = 32'sd0;
        y_abs       = 16'sd0;

        // --- Lookup + interpolação ---
        if (x_abs_u >= {1'b0, X5[15:0]}) begin
            y_abs = SAT_POS;
        end else begin
            if      (x_abs_u < {1'b0, X1[15:0]}) begin x0_seg_u = X0[15:0]; y0_seg = Y0; slope_seg = S01; end
            else if (x_abs_u < {1'b0, X2[15:0]}) begin x0_seg_u = X1[15:0]; y0_seg = Y1; slope_seg = S12; end
            else if (x_abs_u < {1'b0, X3[15:0]}) begin x0_seg_u = X2[15:0]; y0_seg = Y2; slope_seg = S23; end
            else if (x_abs_u < {1'b0, X4[15:0]}) begin x0_seg_u = X3[15:0]; y0_seg = Y3; slope_seg = S34; end
            else                                  begin x0_seg_u = X4[15:0]; y0_seg = Y4; slope_seg = S45; end

            delta_x32   = $signed({15'd0, x_abs_u}) - $signed({16'd0, x0_seg_u});
            interp_full = (delta_x32 * $signed(slope_seg)) >>> Q_FRAC;

            // FIX: clamp intermediário só no positivo (y_abs é magnitude)
            y_abs = y0_seg + interp_full[15:0];
            if      (y_abs > SAT_POS) y_abs = SAT_POS;
            else if (y_abs < 16'sd0)  y_abs = 16'sd0;
        end

        // --- Aplica sinal ---
        y_raw = sign_neg ? -y_abs : y_abs;

        // FIX: saturação final separada, após aplicar sinal
        if      (y_raw > SAT_POS) y_out = SAT_POS;
        else if (y_raw < SAT_NEG) y_out = SAT_NEG;
        else                      y_out = y_raw;
    end

endmodule