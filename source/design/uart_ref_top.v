module top_ref #(parameter clk_freq=50000000, baud_rate=2400, width=8)(
    input              sys_clk,
    input              sys_rst,
    input              xmit_h,
    input  [width-1:0] xmit_data_h,
    input              uart_rec_data_h,
    output             baud_op_clk,
    output             uart_xmit_data_h,
    output             xmit_done_h,
    output [width-1:0] rec_data_h,
    output             rec_ready,
    output             rec_busy,
    output             xmit_active,
    output [width-1:0] shift_out,
    output [3:0]       bit_index
);
    baud_rate #(.freq(clk_freq), .baudr(baud_rate)) b1 (
        .sys_clk  (sys_clk),
        .sys_rst  (sys_rst),
        .uart_clk (baud_op_clk)
    );
    uart_tx_ref #(.width(width)) tx_ref_inst (
        .baud_op_clk     (baud_op_clk),
        .sys_rst         (sys_rst),
        .xmit_h          (xmit_h),
        .xmit_data_h     (xmit_data_h),
        .xmit_done_h     (xmit_done_h),
        .xmit_active     (xmit_active),
        .uart_xmit_data_h(uart_xmit_data_h)
    );
    uart_rx_ref #(.width(width)) rx_ref_inst (
        .sys_rst         (sys_rst),
        .baud_op_clk     (baud_op_clk),
        .uart_rec_data_h (uart_rec_data_h),
        .rec_busy        (rec_busy),
        .rec_ready       (rec_ready),
        .rec_data_h      (rec_data_h),
        .shift_out       (shift_out),
        .bit_index       (bit_index)
    );
endmodule
