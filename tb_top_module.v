// Escala de tempo: 1 nanosegundo de passo / 1 picosegundo de precisão
`timescale 1ns/1ps

module tb_top_module();

    // 1. Declaração dos sinais virtuais (reg para entradas, wire para saídas)
    reg clk;
    reg [4:0] sw;
    reg [3:0] key;
    wire [6:0] hex0;
    wire [6:0] hex1;

    // 2. Instanciação do seu Top Module (DUT - Device Under Test)
    top_module dut (
        .CLOCK_50(clk),
        .SW(sw),
        .KEY(key),
        .HEX0(hex0),
        .HEX1(hex1)
    );

    // 3. Gerador de Clock (50MHz = Período de 20ns)
    // Inverte o sinal a cada 10ns
    always #10 clk = ~clk;

    // 4. A Estratégia de Teste (O que acontece na linha do tempo)
    initial begin
        // Tempo 0: Estado Inicial
        clk = 0;
        sw = 5'b00000;
        key = 4'b1111; // Lógica invertida: 1 significa botão solto

        // --- INÍCIO DA SIMULAÇÃO ---
        $display("Iniciando Simulacao...");

        // Aperta e solta o Reset (KEY[0])
        #20; 
        key[0] = 0; // Aperta
        #20;
        key[0] = 1; // Solta
        #20;

        // --- TESTE 1: INICIAR INFERÊNCIA (START) ---
        $display("Enviando comando START...");
        sw = 5'b01000; // Opcode 0100 (START)
        #20;
        key[3] = 0;    // Aperta Execute (KEY[3])
        #20;
        key[3] = 1;    // Solta Execute
        
        // Aguarda um tempo longo para a rede neural calcular
        // (Isso depende de quantos ciclos sua FSM leva para multiplicar tudo)
        #50000; 

        // --- TESTE 2: REQUISITAR RESULTADO (STATUS) ---
        $display("Enviando comando STATUS...");
        sw = 5'b01010; // Opcode 0101 (STATUS)
        #20;
        key[3] = 0;    // Aperta Execute
        #20;
        key[3] = 1;    // Solta Execute

        // Espera um pouco para ver o resultado no HEX1
        #100;

        $display("Fim da Simulacao.");
        $stop; // Pausa o ModelSim
    end

endmodule