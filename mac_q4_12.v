module mac_q4_12 (
    input clk,
    input reset,
    input enable,    // Ativa a acumulação [cite: 1]
    input clear,     // Zera o acumulador para novo neurônio [cite: 1]
    input signed [15:0] a,
    input signed [15:0] b,
    input signed [15:0] bias, 
    input add_bias,           // Flag para somar o bias [cite: 1]
    output reg signed [15:0] accumulator [cite: 2]
);

    wire signed [31:0] mult_result; [cite: 2]
    wire signed [15:0] trunc_mult; [cite: 2]

    // Multiplicação Q4.12 * Q4.12 resultando em Q8.24 [cite: 3]
    assign mult_result = a * b; [cite: 3]
    
    // Truncamento para retornar ao formato Q4.12 original [cite: 4]
    assign trunc_mult = mult_result[27:12]; [cite: 4]

    always @(posedge clk or posedge reset) begin [cite: 5]
        if (reset) begin
            accumulator <= 16'd0; [cite: 5]
        end else if (clear) begin
            accumulator <= 16'd0; [cite: 6]
        end else if (enable) begin
            if (add_bias) begin
                // Soma o bias ao acumulador no ciclo final [cite: 7]
                accumulator <= accumulator + bias; [cite: 7]
            end else begin
                // Acúmulo normal da multiplicação dos pixels [cite: 8]
                accumulator <= accumulator + trunc_mult; [cite: 8]
            end
        end
    end
endmodule
