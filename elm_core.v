// --- elm_core.v ---
module elm_core (
    input clk,
    input reset,
    input [31:0] instruction,
    input execute,

    // Interface com a Memória de Imagem
    output reg [9:0]  img_addr,
    input  [15:0]     img_data_out,
    output reg        img_we,
    output reg [15:0] img_data_in,

    // Interface com a Memória de Pesos W_in
    output reg [16:0] w_in_addr,
    input  [15:0]     w_in_data_out,

    // Interface com a Memória de Bias
    output reg [6:0]  bias_addr,
    input  [15:0]     bias_data_out,

    // Interface com a Memória de Pesos Beta
    output reg [10:0] beta_addr,
    input  [15:0]     beta_data_out,

    // Sinais de Status e Resultado Final
    output reg busy,
    output reg done,
    output reg error,
    output reg [3:0] result
);

    wire [3:0] opcode = instruction[31:28];
    
    // Opcodes
    parameter START     = 4'b0100;
    parameter STATUS    = 4'b0101;
    parameter CHECK_MEM = 4'b1111;

    // --- MÁQUINA DE ESTADOS EXPANDIDA ---
    parameter IDLE           = 4'd0;
    parameter VERIFY_MEM     = 4'd1;
    parameter ERR            = 4'd2;
    // Fase 1: Camada Oculta
    parameter P1_START       = 4'd3;
    parameter P1_FETCH       = 4'd4;
    parameter P1_MAC         = 4'd5;
    parameter P1_BIAS        = 4'd6;
    parameter P1_ACT_STORE   = 4'd7;
    // Fase 2: Camada de Saída
    parameter P2_START       = 4'd8;
    parameter P2_FETCH       = 4'd9;
    parameter P2_MAC         = 4'd10;
    parameter P2_ARGMAX      = 4'd11;
    
    reg [3:0] state, next_state;

    // --- REGISTRADORES DE CONTROLE E PONTEIROS ---
    reg mem_error_flag, done_flag;
    
    reg [9:0] pixel_cnt;    // 0 a 783
    reg [6:0] hidden_cnt;   // 0 a 127
    reg [3:0] output_cnt;   // 0 a 9
    
    reg [16:0] win_ptr;     // Ponteiro linear para W_in (0 a 100351)
    reg [10:0] beta_ptr;    // Ponteiro linear para Beta (0 a 1279)

    // Memória RAM interna para os neurônios ocultos (H)
    reg signed [15:0] h_ram [0:127];
    reg signed [15:0] h_data_out;

    // --- SINAIS DO DATAPATH ---
    reg mac_enable, mac_clear, mac_add_bias;
    wire signed [15:0] mac_acc_out;
    
    wire signed [15:0] tanh_out;
    reg argmax_enable;
    wire [3:0] argmax_pred;

    // --- INSTANCIAÇÃO DAS TROPAS---

    // MAC: O motor de multiplicação e acúmulo
    // Usa multiplexadores na entrada para alternar entre a Fase 1 e a Fase 2
    wire signed [15:0] mac_in_a = (state >= P2_START) ? h_data_out : img_data_out;
    wire signed [15:0] mac_in_b = (state >= P2_START) ? beta_data_out : w_in_data_out;

    mac_q4_12 mac_inst (
        .clk(clk),
        .reset(reset),
        .enable(mac_enable),
        .clear(mac_clear),
        .a(mac_in_a),
        .b(mac_in_b),
        .bias(bias_data_out),
        .add_bias(mac_add_bias),
        .accumulator(mac_acc_out)
    );

    // Ativação Tanh
    tanh_activation tanh_inst (
        .data_in(mac_acc_out),
        .data_out(tanh_out)
    );

    // Argmax: Seleciona a melhor probabilidade
    argmax_unit argmax_inst (
        .clk(clk),
        .reset(reset || (state == IDLE && execute && opcode == START)), // Limpa ao iniciar novo Start
        .enable(argmax_enable),
        .current_index(output_cnt),
        .current_val(mac_acc_out),
        .predicted_digit(argmax_pred)
    );

    // --- LÓGICA SEQUENCIAL---
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            mem_error_flag <= 0;
            done_flag <= 0;
            
            pixel_cnt <= 0;
            hidden_cnt <= 0;
            output_cnt <= 0;
            win_ptr <= 0;
            beta_ptr <= 0;
            
            img_addr <= 0;
            w_in_addr <= 0;
            bias_addr <= 0;
            beta_addr <= 0;
            
            mac_enable <= 0;
            mac_clear <= 0;
            mac_add_bias <= 0;
            argmax_enable <= 0;
            result <= 4'd0;
            
        end else begin
            state <= next_state;
            
            // Padrões de pulso limpos a cada ciclo
            mac_enable <= 0;
            mac_clear <= 0;
            mac_add_bias <= 0;
            argmax_enable <= 0;

            case (state)
                IDLE: begin
                    if (execute) begin
                        if (opcode == START) begin
                            done_flag <= 0;
                            hidden_cnt <= 0;
                            win_ptr <= 0;
                        end else if (opcode == CHECK_MEM) begin
                            done_flag <= 0;
                            bias_addr <= 0;
                        end else if (opcode == STATUS) begin
                            result <= argmax_pred; // Atualiza o display final
                        end
                    end
                end

                VERIFY_MEM: begin
                    if (bias_data_out == 16'h0000) mem_error_flag <= 1;
                    else begin mem_error_flag <= 0; done_flag <= 1; end
                end

                // ==========================================
                // FASE 1: MULTIPLICAÇÃO DA CAMADA OCULTA
                // ==========================================
                P1_START: begin
                    mac_clear <= 1;        // Zera o MAC para o novo neurônio
                    pixel_cnt <= 0;        // Volta ao primeiro pixel
                    img_addr <= 0;
                    w_in_addr <= win_ptr;  // Mantém o ponteiro de pesos avançando
                end

                P1_FETCH: begin
                    // Ciclo de atraso para as memórias RAM entregarem os dados
                end

                P1_MAC: begin
                    mac_enable <= 1;       // Acumula
                    pixel_cnt <= pixel_cnt + 1;
                    win_ptr <= win_ptr + 1;
                    
                    // Prepara o endereço do próximo ciclo
                    img_addr <= pixel_cnt + 1;
                    w_in_addr <= win_ptr + 1;
                end

                P1_BIAS: begin
                    bias_addr <= hidden_cnt; // Pede o bias deste neurônio
                end

                P1_ACT_STORE: begin
                    mac_enable <= 1;
                    mac_add_bias <= 1;       // Adiciona o bias ao MAC
                    // No mesmo instante, o Tanh calcula. Salva na memória interna:
                    h_ram[hidden_cnt] <= tanh_out; 
                    hidden_cnt <= hidden_cnt + 1;
                    beta_ptr <= 0;           // Prepara o ponteiro para a Fase 2
                    output_cnt <= 0;
                end

                // ==========================================
                // FASE 2: MULTIPLICAÇÃO DA CAMADA DE SAÍDA
                // ==========================================
                P2_START: begin
                    mac_clear <= 1;
                    hidden_cnt <= 0;
                    beta_addr <= beta_ptr;
                    h_data_out <= h_ram[0]; // Lê o primeiro H
                end

                P2_FETCH: begin
                    // Atraso de leitura (Beta)
                end

                P2_MAC: begin
                    mac_enable <= 1;
                    hidden_cnt <= hidden_cnt + 1;
                    beta_ptr <= beta_ptr + 1;
                    
                    beta_addr <= beta_ptr + 1;
                    h_data_out <= h_ram[hidden_cnt + 1];
                end

                P2_ARGMAX: begin
                    argmax_enable <= 1; // Salva o maior valor
                    output_cnt <= output_cnt + 1;
                end

            endcase
            
            // Setar Done Flag quando tudo terminar
            if (state == P2_ARGMAX && output_cnt == 9) begin
                done_flag <= 1;
            end
        end
    end

    // --- LÓGICA DE PRÓXIMO ESTADO ---
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (execute) begin
                    if (opcode == START) next_state = P1_START;
                    else if (opcode == CHECK_MEM) next_state = VERIFY_MEM;
                end
            end
            
            VERIFY_MEM: next_state = mem_error_flag ? ERR : IDLE;
            ERR:        next_state = ERR; // Preso até o reset
            
            // Loop da Fase 1
            P1_START:     next_state = P1_FETCH;
            P1_FETCH:     next_state = P1_MAC;
            P1_MAC:       next_state = (pixel_cnt == 783) ? P1_BIAS : P1_FETCH;
            P1_BIAS:      next_state = P1_ACT_STORE; // Pede o bias e vai armazenar
            P1_ACT_STORE: next_state = (hidden_cnt == 127) ? P2_START : P1_START;
            
            // Loop da Fase 2
            P2_START:     next_state = P2_FETCH;
            P2_FETCH:     next_state = P2_MAC;
            P2_MAC:       next_state = (hidden_cnt == 127) ? P2_ARGMAX : P2_FETCH;
            P2_ARGMAX:    next_state = (output_cnt == 9) ? IDLE : P2_START;
            
        endcase
    end

    // --- SAÍDAS DE STATUS PARA O DISPLAY ---
    always @(*) begin
        busy  = (state != IDLE && state != ERR && done_flag == 0);
        error = (state == ERR);
        done  = (state == IDLE && done_flag == 1'b1);
    end

endmodule