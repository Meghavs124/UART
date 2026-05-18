`timescale 1ns / 1ns
module uart #(parameter clk_freq=50000000,baud_rate=2400,width=8)(
input sys_clk,
input sys_rst,
input xmit_h,
input [width-1:0] xmit_data_h,
input uart_rec_data_h,
output baud_op_clk,
output uart_xmit_data_h,
output xmit_done_h,
output [width-1:0] rec_data_h,
output rec_ready,
output rec_busy,
output xmit_active
);



baud #(.clk_freq(clk_freq),.baud_rate(baud_rate)) b1 (.sys_clk(sys_clk),.sys_rst(sys_rst),.baud_op_clk(baud_op_clk));
uart_tx #(.width(width)) b2(.baud_op_clk(baud_op_clk),.sys_rst(sys_rst),.xmit_h(xmit_h),.xmit_data_h(xmit_data_h),.xmit_active(xmit_active),.xmit_done_h(xmit_done_h),.uart_xmit_data_h(uart_xmit_data_h));
uart_rx #(.width(width)) b3(.baud_op_clk(baud_op_clk),.sys_rst(sys_rst),.uart_rec_data_h(uart_xmit_data_h),.rec_ready(rec_ready),.rec_busy(rec_busy),.rec_data_h(rec_data_h));
endmodule
