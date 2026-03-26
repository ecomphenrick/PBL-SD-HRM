module pbl (
    input  wire clk,
    input  wire reset,
    input  wire start,   // dispara a transição READY -> BUSY
    input  wire ok,      // sinal de sucesso  -> DONE
    input  wire err,     // sinal de erro     -> ERROR
    output reg  done,
    output reg  error
);

localparam READY = 2'b00;
localparam BUSY  = 2'b01;
localparam DONE  = 2'b10;
localparam ERROR = 2'b11;

reg [1:0] estado;

always @(posedge clk or posedge reset) begin

    if (reset) begin
        estado <= READY;
        done   <= 0;
        error  <= 0;

    end else begin

        case (estado)

            READY: begin
                done  <= 0;
                error <= 0;
                if (start)
                    estado <= BUSY;
            end

            BUSY: begin
                if (err)
                    estado <= ERROR;       // algo deu errado
                else if (ok)
                    estado <= DONE;        // tudo certo
                // se nenhum dos dois, fica em BUSY
            end

            DONE: begin
                done <= 1;
                // fica aqui até receber reset
            end

            ERROR: begin
                error <= 1;
                // fica aqui até receber reset
            end

        endcase
    end
end

endmodule