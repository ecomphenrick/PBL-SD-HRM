module elm_core (
    input clk,
    input reset,
    input [31:0] instruction,
    input execute,

    // Interface com as Memórias (Omiti as larguras para focar na lógica)
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

    // Estados da FSM (Reduzidos de 5 para 4 estados - IDLE e FINISH unificados)
    parameter IDLE = 2'd0, CALC = 2'd1, VERIFY_MEM = 2'd2, ERR = 2'd3;
    reg [1:0] state, next_state;

    // Flags internas
    reg mem_error_flag;
    reg done_flag; // Substitui o estado FINISH

    // Controle de Estado Sequencial e Flags
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            mem_error_flag <= 0;
            done_flag <= 0;
            bias_addr <= 7'd0;
        end else begin
            state <= next_state;
            
            // Tratamento no estado IDLE
            if (state == IDLE) begin
                if (execute) begin
                    if (opcode == START) begin
                        done_flag <= 1'b0; // Apaga o DONE ao iniciar novo cálculo
                    end 
                    else if (opcode == CHECK_MEM) begin
                        done_flag <= 1'b0; // Apaga o DONE ao iniciar verificação
                        bias_addr <= 7'd0; // Prepara para ler o endereço 0
                    end
                end
            end
            
            // Tratamento no estado VERIFY_MEM
            if (state == VERIFY_MEM) begin
                if (bias_data_out == 16'h0000) begin
                    mem_error_flag <= 1'b1; // Erro de memória vazia
                end else begin
                    mem_error_flag <= 1'b0; 
                    done_flag <= 1'b1; // Seta o DONE ao concluir a verificação com sucesso
                end
            end

            // Tratamento no final do estado CALC (Simulação)
            if (state == CALC) begin
                // Lógica da rede neural vai aqui. 
                // Quando o contador de neurônios terminar:
                // if (calculo_terminou) done_flag <= 1'b1;
            end
        end
    end

    // Lógica Combinacional de Próximo Estado
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (execute) begin
                    if (opcode == START) next_state = CALC;
                    else if (opcode == CHECK_MEM) next_state = VERIFY_MEM;
                end
            end
            
            VERIFY_MEM: begin
                if (mem_error_flag) next_state = ERR;
                else next_state = IDLE; // Retorna para IDLE imediatamente (pois done_flag foi setada)
            end
            
            CALC: begin
                // if (calculo_terminou) next_state = IDLE; // Retorna para IDLE
            end
            
            ERR: begin
                // Fica travado no erro. A única saída é o reset de hardware.
            end
        endcase
    end

    // Saídas mapeadas diretamente
    always @(*) begin
        busy  = (state == CALC || state == VERIFY_MEM);
        error = (state == ERR);
        // O sinal 'done' agora é verdadeiro se estivermos em repouso E a flag estiver ativa
        done  = (state == IDLE && done_flag == 1'b1);
    end

endmodule