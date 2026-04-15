module pbl (
    input  wire        clk,
    input  wire        reset,
    input  wire        btn,
    input  wire [9:0]  sw,
    // --- LEDs de status ---
    output wire        led_w,
    output wire        led_bias,
    output wire        led_beta,
    output wire        led_img,
    output wire        led_ready,
    output wire        led_busy,
    output wire        led_done,
    output wire        led_error,
    // --- Snapshot para o display ---
    output wire        disp_ready,
    output wire        disp_busy,
    output wire        disp_done,
    output wire        disp_error,
    // --- Escrita nas RAMs (via ISA) ---
    output wire [9:0]  ctrl_img_addr,
    output wire [15:0] ctrl_img_data,
    output wire        ctrl_img_wren,
    output wire [16:0] ctrl_pesos_addr,
    output wire [15:0] ctrl_pesos_data,
    output wire        ctrl_pesos_wren,
    output wire [6:0]  ctrl_bias_addr,
    output wire [15:0] ctrl_bias_data,
    output wire        ctrl_bias_wren,
    output wire [10:0] ctrl_beta_addr,
    output wire [15:0] ctrl_beta_data,
    output wire        ctrl_beta_wren,
    // --- Resultado ---
    output wire [3:0]  pred,
    // --- Interface leitura: Pesos ---
    output wire [16:0] w_addr,
    input  wire [15:0] w_q,
    // --- Interface leitura: Bias ---
    output wire [6:0]  b_addr,
    input  wire [15:0] b_q,
    // --- Interface leitura: Beta ---
    output wire [10:0] beta_rd_addr,
    input  wire [15:0] beta_rd_q,
    // --- Interface leitura: Img ---
    output wire [9:0]  img_rd_addr,
    input  wire [15:0] img_rd_q,
    // --- Sinal direto de estado para mux ---
    output wire        inferencia_ativa
);

    wire start;
    wire infer_done;
    wire infer_error;

    pbl_ctrl u_ctrl (
        .clk              (clk),
        .reset            (reset),
        .btn              (btn),
        .sw               (sw),
        .infer_done       (infer_done),
        .infer_error      (infer_error),
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
        .start            (start),
        .inferencia_ativa (inferencia_ativa)
    );

    pbl_infer u_infer (
        .clk          (clk),
        .reset        (reset),
        .start        (start),
        .w_addr       (w_addr),
        .w_q          (w_q),
        .b_addr       (b_addr),
        .b_q          (b_q),
        .beta_rd_addr (beta_rd_addr),
        .beta_rd_q    (beta_rd_q),
        .img_rd_addr  (img_rd_addr),
        .img_rd_q     (img_rd_q),
        .pred         (pred),
        .done         (infer_done),
        .error        (infer_error)
    );

endmodule