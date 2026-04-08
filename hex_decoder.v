module hex_decoder (
    input [3:0] bin_in,
    output reg [6:0] hex_out // Mapeamento: 7'b G_F_E_D_C_B_A
);

    always @(*) begin
        case(bin_in)
            4'h0: hex_out = 7'b1000000; // Mostra '0'
            4'h1: hex_out = 7'b1111001; // Mostra '1'
            4'h2: hex_out = 7'b0100100; // Mostra '2'
            4'h3: hex_out = 7'b0110000; // Mostra '3'
            4'h4: hex_out = 7'b0011001; // Mostra '4'
            4'h5: hex_out = 7'b0010010; // Mostra '5'
            4'h6: hex_out = 7'b0000010; // Mostra '6'
            4'h7: hex_out = 7'b1111000; // Mostra '7'
            4'h8: hex_out = 7'b0000000; // Mostra '8'
            4'h9: hex_out = 7'b0010000; // Mostra '9'
            default: hex_out = 7'b1111111; // Apagado para valores inválidos
        endcase
    end

endmodule