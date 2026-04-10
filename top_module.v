module top_module (
    // Clock e Entradas Físicas
    input        CLOCK_50,
    input  [4:0] SW,       // Chaves para Instruções
    input  [3:0] KEY,      // Botões (KEY0 = Reset, KEY3 = Execute)
    
    // Saídas para Visualização
    output [6:0] HEX0,     // Status (IDLE, Busy, Done, Error)
    output [6:0] HEX1,     // Resultado (0-9)
    output [9:0] LEDR      // Resultado em Binário e Flags de Status
);

    // --- Sinais de Controle Internos ---
    wire clk   = CLOCK_50;
    wire reset = ~KEY[0];   // Inversão: Ativo em 1
    wire execute = ~KEY[3]; // Inversão: Ativo em 1
    
    // Montagem da instrução de 32 bits a partir das chaves
    wire [31:0] current_instruction = {SW[4:0], 27'd0};

    // --- Barramentos de Interconexão (Wires) ---
    // Interface da Imagem
    wire [9:0]  img_addr;
    wire [15:0] img_data_out;
    wire [15:0] img_data_in;
    wire        img_we;
    
    // Interface de Pesos e Bias
    wire [16:0] w_in_addr;
    wire [15:0] w_in_data_out;
    wire [6:0]  bias_addr;
    wire [15:0] bias_data_out;
    wire [10:0] beta_addr;
    wire [15:0] beta_data_out;

    // Sinais de Saída do Núcleo
    wire [3:0]  predicted_digit;
    wire        is_busy, is_done, is_error;

    // --- Instanciação dos Módulos ---

    // 1. Sistema de Memórias (Cluster)
    memory_cluster mem_sys (
        .clk(clk),
        .manual_instruction(current_instruction),
        .img_addr(img_addr),
        .img_data_in(img_data_in),
        .img_we(img_we),
        .img_data_out(img_data_out),
        .w_in_addr(w_in_addr),
        .w_in_data_out(w_in_data_out),
        .bias_addr(bias_addr),
        .bias_data_out(bias_data_out),
        .beta_addr(beta_addr),
        .beta_data_out(beta_data_out)
    );

    // 2. Núcleo de Processamento ELM
    elm_core core_inst (
        .clk(clk),
        .reset(reset),
        .instruction(current_instruction),
        .execute(execute),
        // Portas de Memória
        .img_addr(img_addr),
        .img_data_out(img_data_out),
        .w_in_addr(w_in_addr),
        .w_in_data_out(w_in_data_out),
        .bias_addr(bias_addr),
        .bias_data_out(bias_data_out),
        .beta_addr(beta_addr),
        .beta_data_out(beta_data_out),
        // Portas de Saída
        .busy(is_busy),
        .done(is_done),
        .error(is_error),
        .result(predicted_digit)
    );

    // 3. Interface Visual (LEDs e Displays)
    status_display display_status (
        .busy(is_busy), .done(is_done), .error(is_error), .hex_out(HEX0)
    );

    hex_decoder display_result (
        .bin_in(predicted_digit), .hex_out(HEX1)
    );

    // Mapeamento dos LEDs Unitários
    assign LEDR[3:0] = predicted_digit; // Binário do resultado
    assign LEDR[9]   = is_busy;        // LED de processamento
    assign LEDR[8]   = is_error;       // LED de falha de memória

endmodule
