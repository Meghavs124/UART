
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
    reg [$clog2(width):0] index;
    reg                   rx1, rx2;
    reg                   rx2_sampled;
    reg [3:0]        count;
    
    always @(posedge baud_op_clk or negedge sys_rst) begin
        if (!sys_rst) begin rx1 <= 1'b1; rx2 <= 1'b1; end
        else          begin rx1 <= uart_rec_data_h; rx2 <= rx1; end
    end

    always @(posedge baud_op_clk or negedge sys_rst) begin
        if (!sys_rst) begin
            ct          <= idle;
            count       <= 0;
            index       <= 0;
            rec_data_h  <= 0;
            rec_ready   <= 0;
            rec_busy    <= 0;
            rx2_sampled <= 1;
        end
        else begin
            ct <= nt;

            if (ct != nt) count <= 0;
            else          count <= count + 1;

            
            if (ct == data && count == 5)
                rx2_sampled <= rx2;

           
            if (ct == data && count == 6)
                rec_data_h <= {rx2_sampled, rec_data_h[width-1:1]};

            
            if (ct == idle)
                index <= 0;
            else if (ct == data && count == 15)
                index <= index + 1;

           
            if (ct == stop && count == 15 && rx2 != 1'b1)
                rec_data_h <= 0;

            
           /* if (ct == stop && count == 15 && rx2 == 1'b1)
                rec_ready <= 1;
            else
                rec_ready <= 0;

            rec_busy <= (nt != idle);*/
              if (ct == stop && count == 15 && rx2 != 1'b1)
                rec_data_h <= 0;

            // rec_busy: high whenever not idle
            rec_busy <= (nt != idle);

            // rec_ready: inverse of busy
            // HIGH when idle (not receiving), LOW when busy (receiving)
            // Stays HIGH until next start bit pulls it low
            rec_ready <= (nt == idle);
        end
    end

    always @(*) begin
        nt = ct;
        case (ct)
            
            idle: nt = (uart_rec_data_h == 1'b0) ? start : idle;

            
            start: begin
                if (count == 6 && rx2 != 1'b0)
                    nt = idle;          
                else if (count == 15)
                    nt = data;          
                else
                    nt = start;
            end

            data: begin
                if (count == 15)
                    nt = (index == width - 1) ? stop : data;
                else
                    nt = data;
            end

            stop: nt = (count == 15) ? idle : stop;

            default: nt = idle;
        endcase
    end
endmodule 
