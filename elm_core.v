// --- elm_core.v corrigido ---
module elm_core (
    input clk,
    input reset,
    input [31:0] instruction,
    input execute,

    // Interface com as Memórias [cite: 1, 2]
    output reg [9:0]  img_addr,
    input  [15:0]     img_data_out,
    output reg        img_we,
    output reg [15:0] img_data_in,

    output reg [16:0] w_in_addr,
    input  [15:0]     w_in_data_out,

    output reg [6:0]  bias_addr,
    input  [15:0]     bias_data_out,

    output reg [10:0] beta_addr,
    input  [15:0]     beta_data_out,

    // Sinais de Status e Resultado Final [cite: 2]
    output reg busy,
    output reg done,
    output reg error,
    output reg [3:0] result
);

    wire [3:0] opcode = instruction[31:28]; [cite: 3]
    
    // Opcodes [cite: 3, 4]
    parameter START     = 4'b0100;
    parameter STATUS    = 4'b0101;
    parameter CHECK_MEM = 4'b1111;

    // Estados Expandidos para o Datapath 
    parameter IDLE           = 4'd0;
    parameter VERIFY_WAIT    = 4'd1;
    parameter VERIFY_CHECK   = 4'd2;
    parameter ERR            = 4'd3;
    parameter P1_START       = 4'd4;
    parameter P1_FETCH       = 4'd5;
    parameter P1_MAC         = 4'd6;
    parameter P1_BIAS        = 4'd7;
    parameter P1_STORE       = 4'd8;
    parameter P2_START       = 4'd9;
    parameter P2_FETCH       = 4'd10;
    parameter P2_MAC         = 4'd11;
    parameter P2_ARGMAX      = 4'd12;

    reg [3:0] state, next_state; [cite: 6]
    reg done_flag, mem_error_flag; [cite: 6, 7]

    // Contadores e Ponteiros
    reg [9:0]  pixel_cnt;
    reg [6:0]  hidden_cnt;
    reg [3:0]  output_cnt;
    reg [16:0] win_ptr;
    reg [10:0] beta_ptr;

    // RAM interna para Neurônios Ocultos (H)
    reg signed [15:0] h_ram [0:127];
    reg signed [15:0] h_data_curr;

    // Sinais de Controle do Datapath
    reg mac_enable, mac_clear, mac_add_bias;
    wire signed [15:0] mac_acc_out;
    wire signed [15:0] tanh_out;
    reg argmax_enable;
    wire [3:0] argmax_pred;

    // Instanciação dos Módulos Matemáticos [cite: 35, 44]
    mac_q4_12 mac_unit (
        .clk(clk), .reset(reset),
        .enable(mac_enable), .clear(mac_clear),
        .a((state >= P2_START) ? h_data_curr : img_data_out),
        .b((state >= P2_START) ? beta_data_out : w_in_data_out),
        .bias(bias_data_out), .add_bias(mac_add_bias),
        .accumulator(mac_acc_out)
    );

    tanh_activation tanh_unit (
        .data_in(mac_acc_out), .data_out(tanh_out)
    );

    argmax_unit argmax_unit_inst (
        .clk(clk), .reset(reset || (state == IDLE && execute && opcode == START)),
        .enable(argmax_enable), .current_index(output_cnt),
        .current_val(mac_acc_out), .predicted_digit(argmax_pred)
    );

    // Lógica Sequencial [cite: 8, 9]
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            done_flag <= 0;
            mem_error_flag <= 0;
            result <= 4'd0;
            {pixel_cnt, hidden_cnt, output_cnt, win_ptr, beta_ptr} <= 0;
        end else begin
            state <= next_state;
            mac_enable <= 0; mac_clear <= 0; mac_add_bias <= 0; argmax_enable <= 0;

            case (state)
                IDLE: begin
                    if (execute) begin
                        if (opcode == START) begin
                            done_flag <= 0; hidden_cnt <= 0; win_ptr <= 0;
                        end else if (opcode == CHECK_MEM) begin
                            done_flag <= 0; bias_addr <= 7'd0; [cite: 11]
                        end else if (opcode == STATUS) begin
                            result <= argmax_pred; // Atualiza o display final [cite: 15]
                        end
                    end
                end

                VERIFY_CHECK: begin
                    if (bias_data_out == 16'h0000) mem_error_flag <= 1'b1; [cite: 13]
                    else begin mem_error_flag <= 1'b0; done_flag <= 1'b1; end [cite: 15]
                end

                P1_START: begin
                    mac_clear <= 1; pixel_cnt <= 0;
                    img_addr <= 0; w_in_addr <= win_ptr;
                end

                P1_MAC: begin
                    mac_enable <= 1;
                    pixel_cnt <= pixel_cnt + 1;
                    win_ptr <= win_ptr + 1;
                    img_addr <= pixel_cnt + 1;
                    w_in_addr <= win_ptr + 1;
                end

                P1_BIAS: begin
                    bias_addr <= hidden_cnt; // Pede o bias deste neurônio
                end

                P1_STORE: begin
                    mac_enable <= 1; mac_add_bias <= 1;
                    h_ram[hidden_cnt] <= tanh_out;
                    hidden_cnt <= hidden_cnt + 1;
                end

                P2_START: begin
                    mac_clear <= 1; hidden_cnt <= 0;
                    beta_addr <= beta_ptr; h_data_curr <= h_ram[0];
                end

                P2_MAC: begin
                    mac_enable <= 1;
                    hidden_cnt <= hidden_cnt + 1;
                    beta_ptr <= beta_ptr + 1;
                    beta_addr <= beta_ptr + 1;
                    h_data_curr <= h_ram[hidden_cnt + 1];
                end

                P2_ARGMAX: begin
                    argmax_enable <= 1;
                    output_cnt <= output_cnt + 1;
                end
            endcase
            
            if (state == P2_ARGMAX && output_cnt == 9) done_flag <= 1;
        end
    end

    // Transições de Estado [cite: 18, 19]
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: if (execute) begin
                if (opcode == START) next_state = P1_START;
                else if (opcode == CHECK_MEM) next_state = VERIFY_WAIT;
            end
            VERIFY_WAIT:  next_state = VERIFY_CHECK;
            VERIFY_CHECK: next_state = mem_error_flag ? ERR : IDLE;
            
            P1_START:     next_state = P1_FETCH;
            P1_FETCH:     next_state = P1_MAC;
            P1_MAC:       next_state = (pixel_cnt == 783) ? P1_BIAS : P1_FETCH;
            P1_BIAS:      next_state = P1_STORE;
            P1_STORE:     next_state = (hidden_cnt == 127) ? P2_START : P1_START;
            
            P2_START:     next_state = P2_FETCH;
            P2_FETCH:     next_state = P2_MAC;
            P2_MAC:       next_state = (hidden_cnt == 127) ? P2_ARGMAX : P2_FETCH;
            P2_ARGMAX:    next_state = (output_cnt == 9) ? IDLE : P2_START;
            
            ERR:          next_state = ERR;
            default:      next_state = IDLE;
        endcase
    end

    always @(*) begin
        busy  = (state != IDLE && state != ERR && !done_flag); [cite: 22]
        error = (state == ERR); [cite: 23]
        done  = (state == IDLE && done_flag); [cite: 23]
    end

endmodule
