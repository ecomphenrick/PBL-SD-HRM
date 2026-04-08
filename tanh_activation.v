module tanh_activation (
    input signed [15:0] data_in,
    output reg signed [15:0] data_out
);

    // Hard Tanh: aproximação linear com saturação para formato Q4.12
    always @(*) begin
        if (data_in > 16'sh1000) begin
            // Se maior que 1.0, satura em 1.0
            data_out = 16'sh1000;
        end 
        else if (data_in < -16'sh1000) begin
            // Se menor que -1.0, satura em -1.0
            data_out = -16'sh1000;
        end 
        else begin
            // Região linear: f(x) = x
            data_out = data_in;
        end
    end

endmodule