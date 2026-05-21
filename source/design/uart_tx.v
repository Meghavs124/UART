module uart_tx #(parameter width = 8)(
    input                   baud_op_clk,
    input                   sys_rst,
    input                   xmit_h,
    input  [width-1:0]      xmit_data_h,
    output reg              xmit_done_h,
    output reg              xmit_active,
    output reg              uart_xmit_data_h
);
    localparam idle  = 2'd0,
               start = 2'd1,
               data  = 2'd2,
               stop  = 2'd3;
 
    reg [1:0]             ct, nt;
    reg [3:0]             count;
    reg [$clog2(width):0] index;
    reg [width-1:0]       latched_data;
    reg                   out;
 
    always @(posedge baud_op_clk or negedge sys_rst) begin
        if (!sys_rst) begin
            ct               <= idle;
            count            <= 0;
            index            <= 0;
            latched_data     <= 0;
            uart_xmit_data_h <= 1;
            xmit_done_h      <= 1;
            xmit_active      <= 0;
        end
        else begin
            ct               <= nt;
            uart_xmit_data_h <= out;
 
            if (xmit_h && ct == idle)
                latched_data <= xmit_data_h;
 
            if (ct == idle)       count <= 0;
            else if (nt != ct)    count <= 0;
            else                  count <= count + 1;
 
            if (ct == idle)       index <= 0;
            else if (ct == data && count == 15 && nt == data)
                                  index <= index + 1;
 
            
            if (ct == stop && nt == idle)
                xmit_done_h <= 1'b1;
            else if (ct == idle && xmit_h)
                xmit_done_h <= 1'b0;
 
            xmit_active <= (nt != idle);
        end
    end
 
    always @(*) begin
        nt  = ct;
        out = 1;
        case (ct)
            idle:  begin out = 1; nt = xmit_h ? start : idle; end
            start: begin out = 0; nt = (count == 15) ? data  : start; end
            data:  begin
                out = latched_data[index];
                if (count == 15)
                    nt = (index == width - 1) ? stop : data;
                else
                    nt = data;
            end
            stop:  begin out = 1; nt = (count == 15) ? idle : stop; end
            default: begin out = 1; nt = idle; end
        endcase
    end
endmodule
