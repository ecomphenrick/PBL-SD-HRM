module pbl_ctrl (
    input  wire        clk,
    input  wire        reset,
    input  wire        btn,
    input  wire [9:0]  sw,
    input  wire        infer_done,
    input  wire        infer_error,
    output reg         led_w,
    output reg         led_bias,
    output reg         led_beta,
    output reg         led_img,
    output reg         led_ready,
    output reg         led_busy,
    output reg         led_done,
    output reg         led_error,
    output reg         disp_ready,
    output reg         disp_busy,
    output reg         disp_done,
    output reg         disp_error,
    output reg  [9:0]  ctrl_img_addr,
    output reg  [15:0] ctrl_img_data,
    output reg         ctrl_img_wren,
    output reg  [16:0] ctrl_pesos_addr,
    output reg  [15:0] ctrl_pesos_data,
    output reg         ctrl_pesos_wren,
    output reg  [6:0]  ctrl_bias_addr,
    output reg  [15:0] ctrl_bias_data,
    output reg         ctrl_bias_wren,
    output reg  [10:0] ctrl_beta_addr,
    output reg  [15:0] ctrl_beta_data,
    output reg         ctrl_beta_wren,
    output reg         start,
    output wire        inferencia_ativa
);


    wire [2:0]  opcode = sw[2:0];
    wire [3:0]  iaddr  = sw[6:3];
    wire [2:0]  idado  = sw[9:7];

   
    localparam OP_WRITE_W    = 3'b000;
    localparam OP_WRITE_BIAS = 3'b001;
    localparam OP_WRITE_BETA = 3'b010;
    localparam OP_WRITE_IMG  = 3'b011;
    localparam OP_STATUS     = 3'b110;
    localparam OP_START      = 3'b111;

    localparam READY = 3'd0;
    localparam BUSY  = 3'd1;
    localparam DONE  = 3'd2;
    localparam ERROR = 3'd3;

    reg [2:0] estado;
    reg btn_prev;

    wire confirm_pulse = (btn_prev == 1'b1) && (btn == 1'b0);
    wire all_loaded    = led_w & led_bias & led_beta & led_img;

    assign inferencia_ativa = (estado == BUSY);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            estado          <= READY;
            btn_prev        <= 1'b1;
            led_w           <= 0;
            led_bias        <= 0;
            led_beta        <= 0;
            led_img         <= 0;
            led_ready       <= 1;
            led_busy        <= 0;
            led_done        <= 0;
            led_error       <= 0;
            disp_ready      <= 0;
            disp_busy       <= 0;
            disp_done       <= 0;
            disp_error      <= 0;
            ctrl_img_addr   <= 0;
            ctrl_img_data   <= 0;
            ctrl_img_wren   <= 0;
            ctrl_pesos_addr <= 0;
            ctrl_pesos_data <= 0;
            ctrl_pesos_wren <= 0;
            ctrl_bias_addr  <= 0;
            ctrl_bias_data  <= 0;
            ctrl_bias_wren  <= 0;
            ctrl_beta_addr  <= 0;
            ctrl_beta_data  <= 0;
            ctrl_beta_wren  <= 0;
            start           <= 0;
        end else begin
            btn_prev        <= btn;
            start           <= 0;
            ctrl_img_wren   <= 0;
            ctrl_pesos_wren <= 0;
            ctrl_bias_wren  <= 0;
            ctrl_beta_wren  <= 0;

            case (estado)

                READY: begin
                    led_ready <= 1;
                    if (confirm_pulse) begin
                        case (opcode)

                            OP_WRITE_W: begin
                                ctrl_pesos_addr <= {13'b0, iaddr};
                                ctrl_pesos_data <= {13'b0, idado};
                                ctrl_pesos_wren <= 1;
                                led_w           <= 1;
                            end

                            OP_WRITE_BIAS: begin
                                ctrl_bias_addr <= {3'b0, iaddr};
                                ctrl_bias_data <= {13'b0, idado};
                                ctrl_bias_wren <= 1;
                                led_bias       <= 1;
                            end

                            OP_WRITE_BETA: begin
                                ctrl_beta_addr <= {7'b0, iaddr};
                                ctrl_beta_data <= {13'b0, idado};
                                ctrl_beta_wren <= 1;
                                led_beta       <= 1;
                            end

                            OP_WRITE_IMG: begin
                                ctrl_img_addr <= {6'b0, iaddr};
                                ctrl_img_data <= {13'b0, idado};
                                ctrl_img_wren <= 1;
                                led_img       <= 1;
                            end

                            OP_STATUS: begin
                                disp_ready <= led_ready;
                                disp_busy  <= led_busy;
                                disp_done  <= led_done;
                                disp_error <= led_error;
                            end

                            OP_START: begin
                                if (all_loaded) begin
                                    estado <= BUSY;
                                    start  <= 1;
                                end else begin
                                    estado <= ERROR;
                                end
                            end

                            default: ;

                        endcase
                    end
                end

                BUSY: begin
                    led_ready <= 0;
                    led_busy  <= 1;
                    if (confirm_pulse && opcode == OP_STATUS) begin
                        disp_ready <= led_ready;
                        disp_busy  <= led_busy;
                        disp_done  <= led_done;
                        disp_error <= led_error;
                    end
                    if (infer_done) begin
                        led_busy <= 0;
                        estado   <= DONE;
                    end else if (infer_error) begin
                        led_busy  <= 0;
                        led_error <= 1;
                        estado    <= ERROR;
                    end
                end

                DONE: begin
                    led_done <= 1;
                    if (confirm_pulse && opcode == OP_STATUS) begin
                        disp_ready <= led_ready;
                        disp_busy  <= led_busy;
                        disp_done  <= led_done;
                        disp_error <= led_error;
                    end
                end

                ERROR: begin
                    led_ready <= 0;
                    led_error <= 1;
                    if (confirm_pulse && opcode == OP_STATUS) begin
                        disp_ready <= led_ready;
                        disp_busy  <= led_busy;
                        disp_done  <= led_done;
                        disp_error <= led_error;
                    end
                end

                default: estado <= READY;

            endcase
        end
    end
endmodule