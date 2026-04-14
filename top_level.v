module top_level (
    // --- Globais ---
    input  wire        clk,
    input  wire        reset,
    // --- FSM ---
    input  wire        btn,
    input  wire        btn_start,
    input  wire [2:0]  sw,
    // --- LEDs ---
    output wire        led_w,
    output wire        led_bias,
    output wire        led_beta,
    output wire        led_img,
    output wire        led_ready,
    output wire        led_busy,led_done
    output wire        led_done,
    output wire        led_error,
    // --- Display 7 segmentos ---
    output wire [6:0]  hex0,
	 output wire [6:0]  hex1,
	 output wire [6:0]  hex2,
	 output wire [6:0]  hex3,
	 output wire [6:0]  hex4,
	 output wire [6:0]  hex5,
    // --- Bias (RAM 128x16) ---
    input  wire [6:0]  bias_addr,
    input  wire [15:0] bias_data,
    input  wire        bias_wren,
    output wire [15:0] bias_q,
    // --- Pesos (RAM 100352x16) ---
    input  wire [16:0] pesos_addr,
    input  wire [15:0] pesos_data,
    input  wire        pesos_wren,
    output wire [15:0] pesos_q,
    // --- Beta (RAM 1280x16) ---
    input  wire [10:0] beta_addr,
    input  wire [15:0] beta_data,
    input  wire        beta_wren,
    output wire [15:0] beta_q,
    // --- Img (RAM 784x16) ---
    input  wire [9:0]  img_addr,
    input  wire [15:0] img_data,
    input  wire        img_wren,
    output wire [15:0] img_q
);

    wire [3:0] pred;
	 wire en;

    // =========================================================================
    // Endereços de leitura do pbl
    // =========================================================================
    wire [16:0] pbl_w_addr;
    wire [6:0]  pbl_b_addr;
    wire [10:0] pbl_beta_rd_addr;
    wire [9:0]  pbl_img_rd_addr;
    wire        inferencia_ativa;

    // =========================================================================
    // Mux: usa sinal combinacional direto da FSM
    // sem atraso de 1 ciclo como led_busy teria
    // =========================================================================
    wire [16:0] pesos_addr_mux = inferencia_ativa ? pbl_w_addr       : pesos_addr;
    wire [15:0] pesos_data_mux = inferencia_ativa ? 16'b0            : pesos_data;
    wire        pesos_wren_mux = inferencia_ativa ? 1'b0             : pesos_wren;

    wire [6:0]  bias_addr_mux  = inferencia_ativa ? pbl_b_addr       : bias_addr;
    wire [15:0] bias_data_mux  = inferencia_ativa ? 16'b0            : bias_data;
    wire        bias_wren_mux  = inferencia_ativa ? 1'b0             : bias_wren;

    wire [10:0] beta_addr_mux  = inferencia_ativa ? pbl_beta_rd_addr : beta_addr;
    wire [15:0] beta_data_mux  = inferencia_ativa ? 16'b0            : beta_data;
    wire        beta_wren_mux  = inferencia_ativa ? 1'b0             : beta_wren;

    wire [9:0]  img_addr_mux   = inferencia_ativa ? pbl_img_rd_addr  : img_addr;
    wire [15:0] img_data_mux   = inferencia_ativa ? 16'b0            : img_data;
    wire        img_wren_mux   = inferencia_ativa ? 1'b0             : img_wren;

    // =========================================================================
    // Instâncias
    // =========================================================================
    pbl u_pbl (
        .clk              (clk),
        .reset            (~reset),
        .btn              (btn),
        .btn_start        (btn_start),
        .sw               (sw),
        .led_w            (led_w),
        .led_bias         (led_bias),
        .led_beta         (led_beta),
        .led_img          (led_img),
        .led_ready        (led_ready),
        .led_busy         (led_busy),
        .led_done         (led_done),
        .led_error        (led_error),
        .pred             (pred),
        .w_addr           (pbl_w_addr),
        .w_q              (pesos_q),
        .b_addr           (pbl_b_addr),
        .b_q              (bias_q),
        .beta_rd_addr     (pbl_beta_rd_addr),
        .beta_rd_q        (beta_q),
        .img_rd_addr      (pbl_img_rd_addr),
        .img_rd_q         (img_q),
        .inferencia_ativa (inferencia_ativa)
    );

    hex7seg u_hex0 (
		  .en (led_done),
        .digit (pred),
        .seg0 (hex0),
		  .seg1 (hex1),
		  .seg2 (hex2),
		  .seg3 (hex3),
		  .seg4 (hex4),
		  .seg5 (hex5)
    );

    Bias u_bias (
        .address (bias_addr_mux),
        .clock   (clk),
        .data    (bias_data_mux),
        .wren    (bias_wren_mux),
        .q       (bias_q)
    );
    Pesos u_pesos (
        .address (pesos_addr_mux),
        .clock   (clk),
        .data    (pesos_data_mux),
        .wren    (pesos_wren_mux),
        .q       (pesos_q)
    );
    Beta u_beta (
        .address (beta_addr_mux),
        .clock   (clk),
        .data    (beta_data_mux),
        .wren    (beta_wren_mux),
        .q       (beta_q)
    );
    IMG u_img (
        .address (img_addr_mux),
        .clock   (clk),
        .data    (img_data_mux),
        .wren    (img_wren_mux),
        .q       (img_q)
    );
endmodule