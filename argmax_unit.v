module argmax_unit (
    input clk,
    input reset,
    input enable,           // Pulso indicando que um novo valor de saída está pronto
    input [3:0] current_index,  // Qual dígito (0 a 9) está sendo avaliado agora
    input signed [15:0] current_val,
    output reg [3:0] predicted_digit
);

    reg signed [15:0] max_val;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Inicializa com o menor número possível em complemento de 2 (Q4.12)
            max_val <= 16'sh8000; 
            predicted_digit <= 4'd0;
        end else if (enable) begin
            // Se o valor atual for maior que o máximo registrado, atualiza
            if (current_val > max_val) begin
                max_val <= current_val;
                predicted_digit <= current_index;
            end
        end
    end

endmodule