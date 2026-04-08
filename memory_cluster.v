module memory_cluster (
    input clk,
    
    // Porta para inserção manual de dados via instrução (Marco 1)
    input [31:0] manual_instruction,
    
    // Interface da Memória de Imagem (Leitura e Escrita)
    input [9:0]  img_addr,
    input [15:0] img_data_in,
    input        img_we,
    output [15:0] img_data_out,

    // Interface da Memória de Pesos de Entrada (Apenas Leitura)
    input [16:0] w_in_addr,
    output [15:0] w_in_data_out,

    // Interface da Memória de Bias (Apenas Leitura)
    input [6:0]  bias_addr,
    output [15:0] bias_data_out,

    // Interface da Memória de Pesos de Saída (Apenas Leitura)
    input [10:0] beta_addr,
    output [15:0] beta_data_out
);

    // O endereço de escrita manual vem da instrução [25:16]
    wire [9:0] manual_wr_addr = manual_instruction[25:16];

    // MULTIPLEXADOR DE ENDEREÇO DA IMAGEM:
    // Se o sinal de escrita (img_we) for 1, usamos o endereço manual.
    // Se for 0, usamos o endereço que o núcleo ELM está pedindo para ler.
    wire [9:0] final_img_addr = img_we ? manual_wr_addr : img_addr;

    // --- INSTANCIAÇÕES CORRIGIDAS PARA 1-PORT RAM ---

    imagem_mif ram_img_inst (
        .clock(clk),
        .data(img_data_in),
        .address(final_img_addr), // Porta unificada de endereço
        .wren(img_we),
        .q(img_data_out)
    );

    W_in_q ram_win_inst (
        .clock(clk),
        .data(16'b0),
        .address(w_in_addr),      // Porta unificada de endereço
        .wren(1'b0),
        .q(w_in_data_out)
    );

    b_q ram_bias_inst (
        .clock(clk),
        .data(16'b0),
        .address(bias_addr),      // Porta unificada de endereço
        .wren(1'b0),
        .q(bias_data_out)
    );

    beta_q ram_beta_inst (
        .clock(clk),
        .data(16'b0),
        .address(beta_addr),      // Porta unificada de endereço
        .wren(1'b0),
        .q(beta_data_out)
    );

endmodule