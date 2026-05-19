
 
`timescale 1ns / 1ns
module tb_uart;

    parameter clk_freq  = 76800;
    parameter baud_rate = 2400;
    parameter width     = 8;

    reg              sys_clk;
    reg              sys_rst;
    reg              xmit_h;
    reg  [width-1:0] xmit_data_h;

    wire             baud_op_clk;
    wire             uart_xmit_data_h;
    wire             xmit_done_h;
    wire [width-1:0] rec_data_h;
    wire             rec_ready;
    wire             rec_busy;
    wire             xmit_active;
    reg              uart_rec_data_h;

    uart #(.clk_freq(clk_freq), .baud_rate(baud_rate), .width(width)) DUT (
        .sys_clk          (sys_clk),
        .sys_rst          (sys_rst),
        .xmit_h           (xmit_h),
        .xmit_data_h      (xmit_data_h),
        .uart_rec_data_h  (uart_rec_data_h),
        .baud_op_clk      (baud_op_clk),
        .uart_xmit_data_h (uart_xmit_data_h),
        .xmit_done_h      (xmit_done_h),
        .rec_data_h       (rec_data_h),
        .rec_ready        (rec_ready),
        .rec_busy         (rec_busy),
        .xmit_active      (xmit_active)
    );

    initial sys_clk = 0;
    always  #5 sys_clk = ~sys_clk;
task send_serial;
    input [width-1:0] data;
    integer i;
    begin
        uart_rec_data_h = 0;
        repeat(16) begin
            @(posedge baud_op_clk); #1;
        end

        for (i = 0; i < width; i = i + 1) begin
            uart_rec_data_h = data[i];
            repeat(16) begin
                @(posedge baud_op_clk); #1;
            end
        end

        uart_rec_data_h = 1;
        repeat(16) begin
            @(posedge baud_op_clk); #1;
        end
    end
endtask

    initial begin
        sys_rst         = 0;
        xmit_h          = 0;
        xmit_data_h     = 0;
        uart_rec_data_h = 1;
        #100;
        sys_rst = 1;
        #50;

        fork
            begin
                @(posedge baud_op_clk); #1;
                xmit_data_h = 8'hA5;
                xmit_h      = 1;
                @(posedge baud_op_clk); #1;
                xmit_h      = 0;
                wait(xmit_done_h);
                @(posedge baud_op_clk);
                $display("--------------------------------");
                $display("TRANSMITTED DATA = %h", 8'hA5);
                $display("TX LINE OUT      = %b", uart_xmit_data_h);
                $display("--------------------------------");
            end
            begin
                send_serial(8'hB6);
                $display("--------------------------------");
                $display("RX INJECTED  = %h", 8'hB6);
                $display("RX RECEIVED  = %h", rec_data_h);
                $display("--------------------------------");
            end
        join

        repeat(20) @(posedge baud_op_clk);

        fork
            begin
                @(posedge baud_op_clk); #1;
                xmit_data_h = 8'h3C;
                xmit_h      = 1;
                @(posedge baud_op_clk); #1;
                xmit_h      = 0;
                wait(xmit_done_h);
                @(posedge baud_op_clk);
                $display("--------------------------------");
                $display("TRANSMITTED DATA = %h", 8'h3C);
                $display("TX LINE OUT      = %b", uart_xmit_data_h);
                $display("--------------------------------");
            end
            begin
                send_serial(8'hD4);
                $display("--------------------------------");
                $display("RX INJECTED  = %h", 8'hD4);
                $display("RX RECEIVED  = %h", rec_data_h);
                $display("--------------------------------");
            end
        join

        repeat(20) @(posedge baud_op_clk);
        $finish;
    end

    initial begin
        #10_000_000;
        $display("TIMEOUT");
        $finish;
    end

    initial begin
        $monitor("TIME=%0t uart_tx=%b rx_in=%b busy=%b ready=%b tx_done=%b rec_data=%h",
                  $time, uart_xmit_data_h, uart_rec_data_h,
                  rec_busy, rec_ready, xmit_done_h, rec_data_h);
    end

endmodule
