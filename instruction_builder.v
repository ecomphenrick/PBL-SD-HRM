module instruction_builder (
    input clk,
    input reset,
    input btn_latch,      // Sinal para salvar o byte
    input [9:0] sw,       // Chaves de entrada
    output reg [31:0] instruction_out
);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            instruction_out <= 32'b0;
        end else if (btn_latch) begin
            case(sw[9:8]) // Seleciona a posição do byte
                2'b00: instruction_out[7:0]   <= sw[7:0];
                2'b01: instruction_out[15:8]  <= sw[7:0];
                2'b10: instruction_out[23:16] <= sw[7:0];
                2'b11: instruction_out[31:24] <= sw[7:0];
            endcase
        end
    end

endmodule