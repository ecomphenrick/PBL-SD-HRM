module top_module (
    input CLOCK_50,
    input [4:0] SW,       // Agora usando apenas 5 chaves!
    input [3:0] KEY,
    output [6:0] HEX0,
    output [6:0] HEX1
);

    // Sinais de Controle Globais
    wire clk = CLOCK_50;
    wire reset = ~KEY[0];
    wire btn_exec = ~KEY[3]; // Botão de Executar
    
    // INSTRUÇÃO SIMPLIFICADA (Sem necessidade de Latch)
    // SW[4:1] = Opcode (bits 31:28)
    // SW[0]   = Bit 27
    // Restante = Zeros
    wire [31:0] current_instruction = {SW[4:0], 27'd0};
    
    // Barramentos de Memória
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

    // Sinais de Status
    wire is_busy, is_done, is_error;
    wire [3:0] predicted_digit; 

    // --- INSTÂNCIA 1: Cluster de Memórias ---
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

    // --- INSTÂNCIA 2: Núcleo ELM ---
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

    // --- INSTÂNCIA 3: Displays ---
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

endmodule