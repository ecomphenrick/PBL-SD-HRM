module top_module (
    input CLOCK_50,
    input [4:0] SW,       
    input [3:0] KEY,
    output [6:0] HEX0,
    output [6:0] HEX1,
    output [9:0] LEDR    // ADICIONADO: Barramento para LEDs unitários 
);

    // Sinais de Controle Globais
    wire clk = CLOCK_50;
    wire reset = ~KEY[0];
    wire btn_exec = ~KEY[3];
    
    // Instrução baseada nas chaves [cite: 83]
    wire [31:0] current_instruction = {SW[4:0], 27'd0};

    // Barramentos de Memória [cite: 84, 85, 86, 88]
    wire [9:0]  img_addr;
    wire [15:0] img_data_out;
    wire [15:0] img_data_in;
    wire        img_we;
    wire [16:0] w_in_addr;
    wire [15:0] w_in_data_out;
    wire [6:0]  bias_addr;
    wire [15:0] bias_data_out;
    wire [10:0] beta_addr;
    wire [15:0] beta_data_out;

    // Sinais de Status e Resultado [cite: 86, 87]
    wire is_busy, is_done, is_error;
    wire [3:0] predicted_digit; 

    // --- IMPLEMENTAÇÃO DOS LEDS --- 
    // Mostra o dígito identificado nos 4 LEDs da direita em binário
    assign LEDR[3:0] = predicted_digit; 
    
    // Feedback visual de status nos LEDs da esquerda
    assign LEDR[9]   = is_busy;  // Aceso enquanto o co-processador calcula
    assign LEDR[8]   = is_error; // Aceso se houver erro de leitura (.mif vazio)
    assign LEDR[7:4] = 4'b0000;  // LEDs auxiliares desligados

    // --- INSTÂNCIA 1: Cluster de Memórias --- [cite: 87, 88]
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

    // --- INSTÂNCIA 2: Núcleo ELM --- [cite: 89, 90]
    elm_core core_inst (
        .clk(clk),
        .reset(reset),
        .instruction(current_instruction),
        .execute(btn_exec),
        .img_addr(img_addr),
        .img_data_out(img_data_out),
        .img_we(img_we),
        .img_data_in(img_data_in),
        .w_in_addr(w_in_addr),
        .w_in_data_out(w_in_data_out),
        .bias_addr(bias_addr),
        .bias_data_out(bias_data_out),
        .beta_addr(beta_addr),
        .beta_data_out(beta_data_out),
        .busy(is_busy),
        .done(is_done),
        .error(is_error),
        .result(predicted_digit)
    );

    // --- INSTÂNCIA 3: Displays --- [cite: 91, 92]
    status_display display_status (
        .busy(is_busy),
        .done(is_done),
        .error(is_error),
        .hex_out(HEX0)
    );

    hex_decoder display_result (
        .bin_in(predicted_digit),
        .hex_out(HEX1)
    );

endmodule // [cite: 93]
