module pbl (
    input  wire        clk,
    input  wire        reset,
    input  wire        btn,
    input  wire        btn_start,
    input  wire [2:0]  sw,
    // --- LEDs de status ---
    output reg         led_w,
    output reg         led_bias,
    output reg         led_beta,
    output reg         led_img,
    output reg         led_ready,
    output reg         led_busy,
    output reg         led_done,
    output reg         led_error,
    // --- Resultado ---
    output reg  [3:0]  pred,
    // --- Interface leitura: Pesos ---
    output reg  [16:0] w_addr,
    input  wire [15:0] w_q,
    // --- Interface leitura: Bias ---
    output reg  [6:0]  b_addr,
    input  wire [15:0] b_q,
    // --- Interface leitura: Beta ---
    output reg  [10:0] beta_rd_addr,
    input  wire [15:0] beta_rd_q,
    // --- Interface leitura: Img ---
    output reg  [9:0]  img_rd_addr,
    input  wire [15:0] img_rd_q,
    // --- Sinal direto de estado para mux ---
    output wire        inferencia_ativa
);

    localparam integer D      = 784;
    localparam integer H      = 128;
    localparam integer C      = 10;
    localparam integer DATA_W = 16;
    localparam integer ACC_W  = 32;
    localparam integer Q_FRAC = 12;

    localparam READY      = 3'd0;
    localparam STORE_W    = 3'd1;
    localparam STORE_BIAS = 3'd2;
    localparam STORE_BETA = 3'd3;
    localparam STORE_IMG  = 3'd4;
    localparam BUSY       = 3'd5;
    localparam DONE       = 3'd6;
    localparam ERROR      = 3'd7;

    reg [2:0] estado;

    assign inferencia_ativa = (estado == BUSY);

    localparam [4:0] PH_H_ADDR       = 5'd0;
    localparam [4:0] PH_H_WAIT0      = 5'd1;
    localparam [4:0] PH_H_WAIT1      = 5'd2;
    localparam [4:0] PH_H_MAC        = 5'd3;
    localparam [4:0] PH_H_BIAS       = 5'd4;
    localparam [4:0] PH_H_BIAS_WAIT0 = 5'd5;
    localparam [4:0] PH_H_BIAS_WAIT1 = 5'd6;
    localparam [4:0] PH_H_TANH       = 5'd7;
    localparam [4:0] PH_H_TANH_LATCH = 5'd8;
    localparam [4:0] PH_O_ADDR       = 5'd9;
    localparam [4:0] PH_O_WAIT0      = 5'd10;
    localparam [4:0] PH_O_WAIT1      = 5'd11;
    localparam [4:0] PH_O_MAC        = 5'd12;
    localparam [4:0] PH_ARGMAX       = 5'd13;

    reg [4:0] phase;

    reg btn_prev;
    reg btn_start_prev;

    wire confirm_pulse = (btn_prev       == 1'b1) && (btn       == 1'b0);
    wire start_pulse   = (btn_start_prev == 1'b1) && (btn_start == 1'b0);

    wire all_loaded = led_w & led_bias & led_beta & led_img;

    reg [$clog2(D)-1:0] in_idx;
    reg [$clog2(H)-1:0] hid_idx;
    reg [$clog2(C)-1:0] cls_idx;

    reg signed [DATA_W-1:0] h_mem [0:H-1];
    reg signed [ACC_W-1:0]  y_mem [0:C-1];

    reg signed [ACC_W-1:0] acc;
    reg signed [ACC_W-1:0] z_hidden;

    wire [16:0] hid_x784 = ({10'b0, hid_idx} << 9)
                          + ({10'b0, hid_idx} << 8)
                          + ({10'b0, hid_idx} << 4);

    wire [10:0] hid_x10  = ({4'b0, hid_idx} << 3)
                          + ({4'b0, hid_idx} << 1);

    wire signed [ACC_W-1:0] mult_hidden_full,  mult_hidden_scaled;
    wire signed [ACC_W-1:0] mult_output_full,  mult_output_scaled;

    mac_q412 #(.DATA_W(DATA_W), .ACC_W(ACC_W), .Q_FRAC(Q_FRAC)) u_mac_hidden (
        .a              (img_rd_q),
        .b              (w_q),
        .product_full   (mult_hidden_full),
        .product_scaled (mult_hidden_scaled)
    );

    mac_q412 #(.DATA_W(DATA_W), .ACC_W(ACC_W), .Q_FRAC(Q_FRAC)) u_mac_output (
        .a              (h_mem[hid_idx]),
        .b              (beta_rd_q),
        .product_full   (mult_output_full),
        .product_scaled (mult_output_scaled)
    );

    wire signed [DATA_W-1:0] z_sat;
    function signed [DATA_W-1:0] sat32_to_q16;
        input signed [ACC_W-1:0] x;
        begin
            if      (x > 32'sd32767)  sat32_to_q16 =  16'sd32767;
            else if (x < -32'sd32768) sat32_to_q16 = -16'sd32768;
            else                      sat32_to_q16  =  x[DATA_W-1:0];
        end
    endfunction
    assign z_sat = sat32_to_q16(z_hidden);

    // --- Saturação linear (sem tanh_lut) ---
    wire signed [DATA_W-1:0] tanh_out;
    assign tanh_out = (z_sat > 16'sd4095)  ?  16'sd4095 :
                      (z_sat < -16'sd4095) ? -16'sd4095 :
                       z_sat;

    wire [3:0]              pred_argmax;
    wire signed [ACC_W-1:0] max_val_unused;
    argmax10 #(.ACC_W(ACC_W)) u_argmax (
        .y0(y_mem[0]), .y1(y_mem[1]), .y2(y_mem[2]), .y3(y_mem[3]), .y4(y_mem[4]),
        .y5(y_mem[5]), .y6(y_mem[6]), .y7(y_mem[7]), .y8(y_mem[8]), .y9(y_mem[9]),
        .pred    (pred_argmax),
        .max_val (max_val_unused)
    );

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            estado         <= READY;
            phase          <= PH_H_ADDR;
            btn_prev       <= 1'b1;
            btn_start_prev <= 1'b1;
            // FIX: flags iniciam em 0 — nada carregado após reset
            led_w          <= 0;
            led_bias       <= 0;
            led_beta       <= 0;
            led_img        <= 0;
            led_ready      <= 1;
            led_busy       <= 0;
            led_done       <= 0;
            led_error      <= 0;
            pred           <= 0;
            in_idx         <= 0;
            hid_idx        <= 0;
            cls_idx        <= 0;
            acc            <= 0;
            z_hidden       <= 0;
            w_addr         <= 0;
            b_addr         <= 0;
            beta_rd_addr   <= 0;
            img_rd_addr    <= 0;
            for (i = 0; i < H; i = i + 1) h_mem[i] <= 0;
            for (i = 0; i < C; i = i + 1) y_mem[i] <= 0;
        end else begin
            btn_prev       <= btn;
            btn_start_prev <= btn_start;

            case (estado)

                READY: begin
                    led_ready <= 1;
                    if (confirm_pulse) begin
                        case (sw)
                            3'b000: estado <= STORE_W;
                            3'b001: estado <= STORE_BIAS;
                            3'b010: estado <= STORE_BETA;
                            3'b011: estado <= STORE_IMG;
                            default: estado <= READY;
                        endcase
                    end else if (start_pulse) begin
                        if (all_loaded) begin
                            estado   <= BUSY;
                            phase    <= PH_H_ADDR;
                            in_idx   <= 0;
                            hid_idx  <= 0;
                            cls_idx  <= 0;
                            acc      <= 0;
                            z_hidden <= 0;
                            pred     <= 0;
                            for (i = 0; i < H; i = i + 1) h_mem[i] <= 0;
                            for (i = 0; i < C; i = i + 1) y_mem[i] <= 0;
                        end else begin
                            estado <= ERROR;
                        end
                    end
                end

                // FIX: STORE states setam flag para 1 (carregado com sucesso)
                STORE_W:    begin led_w    <= 1; estado <= READY; end
                STORE_BIAS: begin led_bias <= 1; estado <= READY; end
                STORE_BETA: begin led_beta <= 1; estado <= READY; end
                STORE_IMG:  begin led_img  <= 1; estado <= READY; end

                BUSY: begin
                    led_ready <= 0;
                    led_busy  <= 1;

                    case (phase)
                        PH_H_ADDR: begin
                            img_rd_addr <= in_idx[9:0];
                            w_addr      <= hid_x784 + {7'b0, in_idx};
                            phase       <= PH_H_WAIT0;
                        end
                        PH_H_WAIT0: phase <= PH_H_WAIT1;
                        PH_H_WAIT1: phase <= PH_H_MAC;
                        PH_H_MAC: begin
                            acc <= acc + mult_hidden_scaled;
                            if (in_idx == D-1) begin
                                in_idx <= 0;
                                phase  <= PH_H_BIAS;
                            end else begin
                                in_idx <= in_idx + 1'b1;
                                phase  <= PH_H_ADDR;
                            end
                        end
                        PH_H_BIAS: begin
                            b_addr <= hid_idx[6:0];
                            phase  <= PH_H_BIAS_WAIT0;
                        end
                        PH_H_BIAS_WAIT0: phase <= PH_H_BIAS_WAIT1;
                        PH_H_BIAS_WAIT1: phase <= PH_H_TANH;
                        PH_H_TANH: begin
                            z_hidden <= acc + {{(ACC_W-DATA_W){b_q[DATA_W-1]}}, b_q};
                            phase    <= PH_H_TANH_LATCH;
                        end
                        PH_H_TANH_LATCH: begin
                            h_mem[hid_idx] <= tanh_out;
                            acc            <= 0;
                            z_hidden       <= 0;
                            if (hid_idx == H-1) begin
                                hid_idx <= 0;
                                cls_idx <= 0;
                                phase   <= PH_O_ADDR;
                            end else begin
                                hid_idx <= hid_idx + 1'b1;
                                phase   <= PH_H_ADDR;
                            end
                        end
                        PH_O_ADDR: begin
                            beta_rd_addr <= hid_x10 + {7'b0, cls_idx};
                            phase        <= PH_O_WAIT0;
                        end
                        PH_O_WAIT0: phase <= PH_O_WAIT1;
                        PH_O_WAIT1: phase <= PH_O_MAC;
                        PH_O_MAC: begin
                            if (hid_idx == H-1) begin
                                y_mem[cls_idx] <= acc + mult_output_scaled;
                                acc            <= 0;
                                hid_idx        <= 0;
                                if (cls_idx == C-1) begin
                                    cls_idx <= 0;
                                    phase   <= PH_ARGMAX;
                                end else begin
                                    cls_idx <= cls_idx + 1'b1;
                                    phase   <= PH_O_ADDR;
                                end
                            end else begin
                                acc     <= acc + mult_output_scaled;
                                hid_idx <= hid_idx + 1'b1;
                                phase   <= PH_O_ADDR;
                            end
                        end
                        PH_ARGMAX: begin
                            pred     <= pred_argmax;
                            led_busy <= 0;
                            estado   <= DONE;
                        end
                        default: begin
                            led_error <= 1;
                            led_busy  <= 0;
                            estado    <= ERROR;
                        end
                    endcase
                end

                DONE:  begin led_done  <= 1; end
                ERROR: begin led_ready <= 0; led_error <= 1; end
                default: estado <= READY;
            endcase
        end
    end
endmodule