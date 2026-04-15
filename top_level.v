module top_level (
    // --- Globais ---
    input  wire        clk,
    input  wire        reset,
    // --- FSM ---
    input  wire        btn,
    input  wire [9:0]  sw,              // atualizado de 3 para 10 bits (atualizar pin assignments)
    // --- LEDs ---
    output wire        led_w,
    output wire        led_bias,
    output wire        led_beta,
    output wire        led_img,
    output wire        led_ready,
    output wire        led_busy,
    output wire        led_done,
    output wire        led_error,
    // --- Display 7 segmentos ---
    output wire [6:0]  hex0,
    output wire [6:0]  hex1,
    output wire [6:0]  hex2,
    output wire [6:0]  hex3,
    output wire [6:0]  hex4,
    output wire [6:0]  hex5,
    // --- Bias (RAM 128x16) --- mantidas para compatibilidade com pin assignments
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
    wire       inferencia_ativa;

    // Endereços de leitura do pbl_infer
    wire [16:0] pbl_w_addr;
    wire [6:0]  pbl_b_addr;
    wire [10:0] pbl_beta_rd_addr;
    wire [9:0]  pbl_img_rd_addr;

    // Escrita via ISA (pbl_ctrl)
    wire [9:0]  ctrl_img_addr;
    wire [15:0] ctrl_img_data;
    wire        ctrl_img_wren;
    wire [16:0] ctrl_pesos_addr;
    wire [15:0] ctrl_pesos_data;
    wire        ctrl_pesos_wren;
    wire [6:0]  ctrl_bias_addr;
    wire [15:0] ctrl_bias_data;
    wire        ctrl_bias_wren;
    wire [10:0] ctrl_beta_addr;
    wire [15:0] ctrl_beta_data;
    wire        ctrl_beta_wren;

    // Snapshot para display
    wire disp_ready, disp_busy, disp_done, disp_error;

    // =========================================================================
    // Mux de acesso às RAMs
    // Prioridade 1: inferencia_ativa  → pbl_infer lê
    // Prioridade 2: ctrl_*_wren       → pbl_ctrl escreve via ISA
    // Prioridade 3: externo           → portas originais (JTAG, fallback)
    // =========================================================================

    wire [9:0]  img_addr_mux   = inferencia_ativa ? pbl_img_rd_addr  :
                                  ctrl_img_wren   ? ctrl_img_addr    : img_addr;
    wire [15:0] img_data_mux   = inferencia_ativa ? 16'b0            :
                                  ctrl_img_wren   ? ctrl_img_data    : img_data;
    wire        img_wren_mux   = inferencia_ativa ? 1'b0             :
                                  ctrl_img_wren   ? 1'b1             : img_wren;

    wire [16:0] pesos_addr_mux = inferencia_ativa ? pbl_w_addr        :
                                  ctrl_pesos_wren ? ctrl_pesos_addr   : pesos_addr;
    wire [15:0] pesos_data_mux = inferencia_ativa ? 16'b0             :
                                  ctrl_pesos_wren ? ctrl_pesos_data   : pesos_data;
    wire        pesos_wren_mux = inferencia_ativa ? 1'b0              :
                                  ctrl_pesos_wren ? 1'b1              : pesos_wren;

    wire [6:0]  bias_addr_mux  = inferencia_ativa ? pbl_b_addr       :
                                  ctrl_bias_wren  ? ctrl_bias_addr   : bias_addr;
    wire [15:0] bias_data_mux  = inferencia_ativa ? 16'b0            :
                                  ctrl_bias_wren  ? ctrl_bias_data   : bias_data;
    wire        bias_wren_mux  = inferencia_ativa ? 1'b0             :
                                  ctrl_bias_wren  ? 1'b1             : bias_wren;

    wire [10:0] beta_addr_mux  = inferencia_ativa ? pbl_beta_rd_addr :
                                  ctrl_beta_wren  ? ctrl_beta_addr   : beta_addr;
    wire [15:0] beta_data_mux  = inferencia_ativa ? 16'b0            :
                                  ctrl_beta_wren  ? ctrl_beta_data   : beta_data;
    wire        beta_wren_mux  = inferencia_ativa ? 1'b0             :
                                  ctrl_beta_wren  ? 1'b1             : beta_wren;

    // =========================================================================
    // Instâncias
    // =========================================================================
    pbl u_pbl (
        .clk              (clk),
        .reset            (~reset),
        .btn              (btn),
        .sw               (sw),
        .led_w            (led_w),
        .led_bias         (led_bias),
        .led_beta         (led_beta),
        .led_img          (led_img),
        .led_ready        (led_ready),
        .led_busy         (led_busy),
        .led_done         (led_done),
        .led_error        (led_error),
        .disp_ready       (disp_ready),
        .disp_busy        (disp_busy),
        .disp_done        (disp_done),
        .disp_error       (disp_error),
        .ctrl_img_addr    (ctrl_img_addr),
        .ctrl_img_data    (ctrl_img_data),
        .ctrl_img_wren    (ctrl_img_wren),
        .ctrl_pesos_addr  (ctrl_pesos_addr),
        .ctrl_pesos_data  (ctrl_pesos_data),
        .ctrl_pesos_wren  (ctrl_pesos_wren),
        .ctrl_bias_addr   (ctrl_bias_addr),
        .ctrl_bias_data   (ctrl_bias_data),
        .ctrl_bias_wren   (ctrl_bias_wren),
        .ctrl_beta_addr   (ctrl_beta_addr),
        .ctrl_beta_data   (ctrl_beta_data),
        .ctrl_beta_wren   (ctrl_beta_wren),
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
        .en        (led_done),
        .digit     (pred),
        .led_ready (disp_ready),
        .led_busy  (disp_busy),
        .led_done  (disp_done),
        .led_error (disp_error),
        .seg0      (hex0),
        .seg1      (hex1),
        .seg2      (hex2),
        .seg3      (hex3),
        .seg4      (hex4),
        .seg5      (hex5)
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