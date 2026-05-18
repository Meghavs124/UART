`timescale 1ns / 1ns

module baud #(parameter clk_freq=5000000,baud_rate=2400)(
	input sys_clk,
	input sys_rst,
	output reg baud_op_clk);
	
	integer count;
	
	parameter count1= (clk_freq)/(16*baud_rate);
	
	always @(posedge sys_clk or negedge sys_rst)
     	begin
			if(!sys_rst) begin
			baud_op_clk<=0;
			count<=0;
			end
			
			else if (count==(count1-1))
			begin
			baud_op_clk<=~baud_op_clk;
			count<=0;
			end
			
			else
			begin
			baud_op_clk<=0;
			count<=count+1;
			end
			
		end
endmodule

