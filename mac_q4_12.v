module mac_q4_12 (
    input clk,
    input reset,
    input enable,    // Ativa a acumulação
    input clear,     // Zera o acumulador (usado ao iniciar um novo neurônio)
    input signed [15:0] a,
    input signed [15:0] b,
    input signed [15:0] bias, // Adicionado no ciclo final do neurônio
    input add_bias,           // Flag para somar o bias ao invés de a*b
    output reg signed [15:0] accumulator
);

    wire signed [31:0] mult_result;
    wire signed [15:0] trunc_mult;

    // Multiplicação com sinal (Q4.12 * Q4.12 = Q8.24)
    assign mult_result = a * b;

    // Truncamento para retornar ao formato Q4.12
    assign trunc_mult = mult_result[27:12];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            accumulator <= 16'd0;
        end else if (clear) begin
            accumulator <= 16'd0;
        end else if (enable) begin
            if (add_bias) begin
                // No último ciclo do neurônio, soma o bias ao acumulador
                accumulator <= accumulator + bias;
            end else begin
                // Ciclos normais: acumula o resultado da multiplicação
                accumulator <= accumulator + trunc_mult;
            end
        end
    end

endmodule