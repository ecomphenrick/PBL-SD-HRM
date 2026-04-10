module elm_core (
    input clk, input reset, input [31:0] instruction, input execute,
    output reg [9:0]  img_addr,   input [15:0] img_data_out,
    output reg        img_we,     output reg [15:0] img_data_in,
    output reg [16:0] w_in_addr,  input [15:0] w_in_data_out,
    output reg [6:0]  bias_addr,  input [15:0] bias_data_out,
    output reg [10:0] beta_addr,  input [15:0] beta_data_out,
    output reg busy, output reg done, output reg error, output reg [3:0] result
);

    // --- Definição de Opcodes ---
    wire [3:0] opcode = instruction[31:28];
    parameter START=4'b0100, STATUS=4'b0101, CHECK_MEM=4'b1111;

    // --- Estados da FSM Completos ---
    parameter IDLE=4'd0, V_WAIT=4'd1, V_CHECK=4'd2, ERR=4'd3;
    parameter P1_START=4'd4, P1_FETCH=4'd5, P1_MAC=4'd6, P1_BIAS=4'd7, P1_ADD=4'd8, P1_STORE=4'd9;
    parameter P2_START=4'd10, P2_FETCH=4'd11, P2_MAC=4'd12, P2_ARGMAX=4'd13;

    reg [3:0]  state, next_state;
    reg [9:0]  pixel_cnt;
    reg [6:0]  hidden_cnt;
    reg [3:0]  output_cnt;
    reg [16:0] win_ptr;
    reg [10:0] beta_ptr;
    reg        done_flag, mem_error_flag;

    // Memória H e Sinais do MAC
    reg signed [15:0] h_ram [0:127];
    reg signed [15:0] h_data_curr;
    reg mac_enable, mac_clear, mac_add_bias, argmax_enable;
    wire signed [15:0] mac_acc_out, tanh_out;
    wire [3:0] argmax_pred;

    // Multiplexador de Entrada do MAC
    wire signed [15:0] mac_a = (state >= P2_START) ? h_data_curr : img_data_out;
    wire signed [15:0] mac_b = (state >= P2_START) ? beta_data_out : w_in_data_out;

    // --- Unidades Matemáticas ---
    mac_q4_12 mac_inst (
        .clk(clk), .reset(reset), .enable(mac_enable), .clear(mac_clear),
        .a(mac_a), .b(mac_b), .bias(bias_data_out), 
        .add_bias(mac_add_bias), .accumulator(mac_acc_out)
    );

    tanh_activation tanh_inst (
        .data_in(mac_acc_out), .data_out(tanh_out)
    );

    argmax_unit argmax_inst (
        .clk(clk), .reset(reset || (state == IDLE && execute && opcode == START)),
        .enable(argmax_enable), .current_index(output_cnt),
        .current_val(mac_acc_out), .predicted_digit(argmax_pred)
    );

    // --- Lógica Sequencial (FSM) ---
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE; 
            {busy, done, error, result} <= 0;
            {pixel_cnt, hidden_cnt, output_cnt, win_ptr, beta_ptr} <= 0;
            done_flag <= 0; mem_error_flag <= 0;
            img_we <= 0; img_data_in <= 0;
        end else begin
            state <= next_state;
            {mac_enable, mac_clear, mac_add_bias, argmax_enable} <= 4'b0000;

            case (state)
                IDLE: if (execute) begin
                    if (opcode == STATUS) result <= argmax_pred; 
                    else if (opcode == START) begin done_flag <= 0; hidden_cnt <= 0; win_ptr <= 0; end
                end
                V_CHECK: if (bias_data_out == 16'h0000) mem_error_flag <= 1; else done_flag <= 1;
                
                // FASE 1: Camada Oculta
                P1_START: begin mac_clear <= 1; pixel_cnt <= 0; img_addr <= 0; w_in_addr <= win_ptr; end
                P1_MAC: begin 
                    mac_enable <= 1; 
                    pixel_cnt <= pixel_cnt + 1; 
                    win_ptr <= win_ptr + 1; 
                    img_addr <= pixel_cnt + 1; 
                    w_in_addr <= win_ptr + 1; 
                end
                P1_BIAS: bias_addr <= hidden_cnt;
                P1_ADD:  begin mac_enable <= 1; mac_add_bias <= 1; end 
                P1_STORE: begin h_ram[hidden_cnt] <= tanh_out; hidden_cnt <= hidden_cnt + 1; end 
                
                // FASE 2: Camada de Saída
                P2_START: begin mac_clear <= 1; hidden_cnt <= 0; beta_addr <= beta_ptr; h_data_curr <= h_ram[0]; end
                P2_MAC: begin 
                    mac_enable <= 1; 
                    hidden_cnt <= hidden_cnt + 1; 
                    beta_ptr <= beta_ptr + 1;
                    beta_addr <= beta_ptr + 1; 
                    if (hidden_cnt < 127) h_data_curr <= h_ram[hidden_cnt + 1]; 
                end
                P2_ARGMAX: begin argmax_enable <= 1; output_cnt <= output_cnt + 1; end 
            endcase
            
            if (state == P2_ARGMAX && output_cnt == 9) done_flag <= 1; 
        end
    end

    // --- Lógica de Próximo Estado ---
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:      if (execute) next_state = (opcode == START) ? P1_START : (opcode == CHECK_MEM ? V_WAIT : IDLE);
            V_WAIT:    next_state = V_CHECK;
            V_CHECK:   next_state = mem_error_flag ? ERR : IDLE;
            ERR:       next_state = ERR;
            
            // Loop Fase 1
            P1_START:  next_state = P1_FETCH;
            P1_FETCH:  next_state = P1_MAC;
            P1_MAC:    next_state = (pixel_cnt == 783) ? P1_BIAS : P1_FETCH;
            P1_BIAS:   next_state = P1_ADD;
            P1_ADD:    next_state = P1_STORE;
            P1_STORE:  next_state = (hidden_cnt == 127) ? P2_START : P1_START;
            
            // Loop Fase 2
            P2_START:  next_state = P2_FETCH;
            P2_FETCH:  next_state = P2_MAC;
            P2_MAC:    next_state = (hidden_cnt == 127) ? P2_ARGMAX : P2_FETCH;
            P2_ARGMAX: next_state = (output_cnt == 9) ? IDLE : P2_START;
            default:   next_state = IDLE;
        endcase
    end

    // --- Status ---
    always @(*) begin
        busy  = (state != IDLE && state != ERR && !done_flag);
        error = (state == ERR || mem_error_flag);
        done  = (state == IDLE && done_flag);
    end
endmodule
