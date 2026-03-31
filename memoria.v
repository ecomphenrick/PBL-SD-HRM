module memoria (

    input wire clk,

    // endereço pesos
    input wire [16:0] addr_w,
    output reg [15:0] peso,

    // endereço vieses
    input wire [6:0] addr_b,
    output reg [15:0] bias

);

// PESOS
(* ram_init_file = "W_in_q.mif", preserve *)
reg [15:0] mem_pesos [0:100351];

always @(posedge clk)
begin
    peso <= mem_pesos[addr_w];
end


// BIAS
(* ram_init_file = "b_q.mif", preserve *)
reg [15:0] mem_bias [0:127];

always @(posedge clk)
begin
    bias <= mem_bias[addr_b];
end

endmodule