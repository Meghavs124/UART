module uart_rx #(parameter width = 8)(
    input                   sys_rst,
    input                   baud_op_clk,
    input                   uart_rec_data_h,
    output reg              rec_busy,
    output reg              rec_ready,
    output reg [width-1:0]  rec_data_h
);
    localparam idle  = 2'd0,
               start = 2'd1,
               data  = 2'd2,
               stop  = 2'd3;

    reg [1:0]             ct, nt;
    reg [3:0]             count;
    reg [$clog2(width):0] index;
    reg                   rx1, rx2;

    
    always @(posedge baud_op_clk or negedge sys_rst) begin
        if (!sys_rst) begin rx1 <= 1'b1; rx2 <= 1'b1; end
        else          begin rx1 <= uart_rec_data_h; rx2 <= rx1; end
    end

    always @(posedge baud_op_clk or negedge sys_rst) begin
        if (!sys_rst) begin
            ct         <= idle;
            count      <= 0;
            index      <= 0;
            rec_data_h <= 0;
            rec_ready  <= 1;
            rec_busy   <= 0;
        end
        else begin
            ct <= nt;

           
            if (ct != nt) count <= 0;
            else          count <= count + 1;

           
            if (ct == data && count == 7)
                rec_data_h <= {rx2, rec_data_h[width-1:1]};  

           
            if (ct == idle)
                index <= 0;
            else if (ct == data && count == 15)
                index <= index + 1;

            
            if (ct == stop && count == 7 && rx2 != 1'b1)
                rec_data_h <= 0;

            rec_ready <= (nt == idle);
            rec_busy  <= (nt != idle);
        end
    end

    always @(*) begin
        nt = ct;
        case (ct)
            idle:  nt = (rx2 == 1'b0) ? start : idle;

            start: begin
                if (count == 12)
                    nt = (rx2 == 1'b0) ? data : idle;
                else
                    nt = start;
            end

            data: begin
                if (count == 15)
                    nt = (index == width - 1) ? stop : data;
                else
                    nt = data;
            end

            stop:  nt = (count == 15) ? idle : stop;
            default: nt = idle;
        endcase
    end
endmodule
