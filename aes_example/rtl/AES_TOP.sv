`timescale 1ns/1ps

import AES_PKG::*;
import UART_PKG::*;

module AES_TOP #(
    parameter longint SYSCLK_HZ = 10_000_000,
    parameter longint BAUD_HZ   = 38_400
)(
    input  logic clkin,
    output logic clkout,
    output logic gpio1,
    input  logic gpio2,
    output logic gpio4,
    input  logic nrst,
    output logic led3
);

    localparam int     TICKS_PER_BIT = 16;
    localparam longint SCALED     = BAUD_HZ * TICKS_PER_BIT * (64'd1 <<< UART_ACC_W);
    localparam logic [UART_ACC_W-1:0] BAUD_INC =
        (SCALED + SYSCLK_HZ/2) / SYSCLK_HZ;

    localparam logic [7:0] CMD_KEY = 8'h6B;
    localparam logic [7:0] CMD_ENC = 8'h70;

    typedef enum logic [2:0] {
        S_CMD,
        S_KEY,
        S_KEYGO,
        S_KEYWAIT,
        S_PT,
        S_ENCGO,
        S_ENCWAIT,
        S_TX
    } cmd_e;

    logic       clk;
    logic [1:0] rst_sync;
    logic       rst;

    assign clk    = clkin;
    assign clkout = clkin;
    assign rst    = rst_sync[1];

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            rst_sync <= 2'b11;
        end else begin
            rst_sync <= {rst_sync[0], 1'b0};
        end
    end

    uart_cfg_t cfg;

    always_comb begin
        cfg             = '0;
        cfg.tx_baud_inc = BAUD_INC;
        cfg.rx_baud_inc = BAUD_INC;
        cfg.data_bits   = 4'd8;
        cfg.parity      = UART_PARITY_NONE;
        cfg.stop_16ths  = 8'd16;
        cfg.flow_en     = 1'b0;
    end

    UART_TX_IF #(.DATA_MAX(8)) tx_io (.clk(clk), .rst(rst));
    UART_RX_IF #(.DATA_MAX(8)) rx_io (.clk(clk), .rst(rst));

    UART_CORE #(
        .DATA_MAX  (8         ),
        .TICKS_PER_BIT(TICKS_PER_BIT),
        .FILTER    (3         )
    ) u_uart (
        .tx_io(tx_io),
        .rx_io(rx_io),
        .cfg  (cfg  )
    );

    logic [7:0] tx_data_r;
    logic       tx_valid_r;

    assign tx_io.data       = tx_data_r;
    assign tx_io.valid      = tx_valid_r;
    assign tx_io.cts_n      = 1'b0;
    assign tx_io.send_break = 1'b0;
    assign rx_io.ready      = 1'b1;
    assign gpio1            = tx_io.txd;
    assign rx_io.rxd        = gpio2;

    logic         aes_update_key;
    logic         aes_encrypt;
    logic         aes_ready;
    logic         aes_key_loaded;
    byte_t [31:0] key_reg;
    byte_t [15:0] pt_reg;
    byte_t [15:0] ct_reg;
    byte_t [15:0] aes_out;

    AES_CORE_ITER u_aes (
        .clk       (clk           ),
        .rst       (rst           ),
        .update_key(aes_update_key),
        .encrypt   (aes_encrypt   ),
        .decrypt   (1'b0          ),
        .keysize   (KS_128        ),
        .key       (key_reg       ),
        .plaintext (pt_reg        ),
        .ciphertext('0            ),
        .ready     (aes_ready     ),
        .key_loaded(aes_key_loaded),
        .data_out  (aes_out       )
    );

    cmd_e       state;
    logic [4:0] cnt;
    logic       trig;
    logic       led;
    logic       busy_seen;

    assign gpio4 = trig;
    assign led3  = led;

    always_ff @(posedge clk) begin
        if (rst) begin
            state          <= S_CMD;
            cnt            <= 'b0;
            key_reg        <= '0;
            pt_reg         <= '0;
            ct_reg         <= '0;
            tx_data_r      <= 'b0;
            tx_valid_r     <= 'b0;
            aes_update_key <= 'b0;
            aes_encrypt    <= 'b0;
            trig           <= 'b0;
            led            <= 'b0;
            busy_seen      <= 'b0;
        end else begin
            state          <= state;
            cnt            <= cnt;
            key_reg        <= key_reg;
            pt_reg         <= pt_reg;
            ct_reg         <= ct_reg;
            tx_data_r      <= tx_data_r;
            tx_valid_r     <= tx_valid_r;
            aes_update_key <= 'b0;
            aes_encrypt    <= 'b0;
            trig           <= trig;
            led            <= led;
            busy_seen      <= busy_seen;

            if (tx_valid_r) begin
                tx_valid_r <= 'b0;
            end

            case (state)
                S_CMD: begin
                    if (rx_io.valid) begin
                        cnt <= 'b0;
                        if (rx_io.data[7:0] == CMD_KEY) begin
                            state <= S_KEY;
                        end else if (rx_io.data[7:0] == CMD_ENC) begin
                            state <= S_PT;
                        end
                    end
                end

                S_KEY: begin
                    if (rx_io.valid) begin
                        key_reg[15 - cnt] <= rx_io.data[7:0];
                        if (cnt == 5'd15) begin
                            cnt   <= 'b0;
                            state <= S_KEYGO;
                        end else begin
                            cnt <= cnt + 'b1;
                        end
                    end
                end

                S_KEYGO: begin
                    if (aes_ready) begin
                        aes_update_key <= 'b1;
                        state          <= S_KEYWAIT;
                    end
                end

                S_KEYWAIT: begin
                    if (!aes_ready) begin
                        busy_seen <= 'b1;
                    end else if (busy_seen) begin
                        busy_seen <= 'b0;
                        state     <= S_CMD;
                    end
                end

                S_PT: begin
                    if (rx_io.valid) begin
                        pt_reg[15 - cnt] <= rx_io.data[7:0];
                        if (cnt == 5'd15) begin
                            cnt   <= 'b0;
                            state <= S_ENCGO;
                        end else begin
                            cnt <= cnt + 'b1;
                        end
                    end
                end

                S_ENCGO: begin
                    if (aes_ready) begin
                        aes_encrypt <= 'b1;
                        trig        <= 'b1;
                        state       <= S_ENCWAIT;
                    end
                end

                S_ENCWAIT: begin
                    if (!aes_ready) begin
                        busy_seen <= 'b1;
                    end else if (busy_seen) begin
                        ct_reg    <= aes_out;
                        busy_seen <= 'b0;
                        trig      <= 'b0;
                        led       <= ~led;
                        state     <= S_TX;
                    end
                end

                S_TX: begin
                    if (!tx_valid_r && tx_io.ready) begin
                        tx_data_r  <= ct_reg[15 - cnt];
                        tx_valid_r <= 'b1;
                        if (cnt == 5'd15) begin
                            cnt   <= 'b0;
                            state <= S_CMD;
                        end else begin
                            cnt <= cnt + 'b1;
                        end
                    end
                end

                default: begin
                    state <= S_CMD;
                end
            endcase
        end
    end

endmodule
