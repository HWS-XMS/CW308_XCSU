`timescale 1ns/1ps

module AES_TOP_TB;
    `include "tb_check.svh"

    localparam real SYSCLK_HZ = 10_000_000.0;
    localparam real BAUD      =     38_400.0;
    localparam real HALF_NS   = 1.0e9 / SYSCLK_HZ / 2.0;
    localparam real BIT_NS    = 1.0e9 / BAUD;

    localparam logic [127:0] KEY = 128'h2b7e151628aed2a6abf7158809cf4f3c;
    localparam logic [127:0] PT  = 128'h3243f6a8885a308d313198a2e0370734;
    localparam logic [127:0] CT  = 128'h3925841d02dc09fbdc118597196a0b32;

    logic clkin = 0;
    logic nrst  = 0;
    logic gpio2 = 1;
    logic gpio1;
    logic gpio4;
    logic led3;
    logic clkout;

    AES_TOP #(
        .SYSCLK_HZ(10_000_000),
        .BAUD_HZ  (    38_400)
    ) dut (
        .clkin (clkin ),
        .clkout(clkout),
        .gpio1 (gpio1 ),
        .gpio2 (gpio2 ),
        .gpio4 (gpio4 ),
        .nrst  (nrst  ),
        .led3  (led3  )
    );

    always #(HALF_NS) clkin = ~clkin;

    int trig_count = 0;
    always @(posedge gpio4) trig_count = trig_count + 1;

    task automatic send_byte(input logic [7:0] b);
        int k;
        gpio2 = 1'b0;
        #(BIT_NS);
        for (k = 0; k < 8; k = k + 1) begin
            gpio2 = b[k];
            #(BIT_NS);
        end
        gpio2 = 1'b1;
        #(BIT_NS);
    endtask

    task automatic recv_byte(output logic [7:0] b, output bit ok);
        int  k;
        real waited;
        b      = 'b0;
        ok     = 1'b0;
        waited = 0.0;
        while (gpio1 !== 1'b0 && waited < 400.0 * BIT_NS) begin
            #(BIT_NS / 16.0);
            waited = waited + BIT_NS / 16.0;
        end
        if (gpio1 === 1'b0) begin
            #(BIT_NS * 1.5);
            for (k = 0; k < 8; k = k + 1) begin
                b[k] = gpio1;
                if (k < 7) begin
                    #(BIT_NS);
                end
            end
            #(BIT_NS);
            ok = (gpio1 === 1'b1);
        end
    endtask

    logic [7:0]   got [0:15];
    logic [127:0] ct_got;
    bit           ok;
    int           i;
    logic         led_before;

    initial begin
        nrst = 1'b0;
        #(40.0 * HALF_NS);
        nrst = 1'b1;
        #(40.0 * HALF_NS);

        `CHK("uart line idles high", gpio1 === 1'b1)
        `CHK("trigger idles low",    gpio4 === 1'b0)

        send_byte(8'h6B);
        for (i = 0; i < 16; i = i + 1) begin
            send_byte(KEY[127 - 8*i -: 8]);
        end
        #(40.0 * BIT_NS);

        `CHK("no trigger during key load", trig_count == 0)

        led_before = led3;

        send_byte(8'h70);
        for (i = 0; i < 16; i = i + 1) begin
            send_byte(PT[127 - 8*i -: 8]);
        end

        for (i = 0; i < 16; i = i + 1) begin
            recv_byte(got[i], ok);
            `CHK($sformatf("ciphertext byte %0d framed", i), ok)
        end

        ct_got = 'b0;
        for (i = 0; i < 16; i = i + 1) begin
            ct_got[127 - 8*i -: 8] = got[i];
        end

        `CHK_EQ("ciphertext matches FIPS-197", ct_got, CT)
        `CHK   ("exactly one trigger pulse",  trig_count == 1)
        `CHK   ("led3 toggled",               led3 !== led_before)

        `TB_SUMMARY("AES_TOP_TB")
    end
endmodule
