module uart_rx_ref #(parameter width = 8)(
    input                   sys_rst,
    input                   baud_op_clk,
    input                   uart_rec_data_h,
    output reg              rec_busy,
    output reg              rec_ready,
    output reg [width-1:0]  rec_data_h,
    output reg [width-1:0]  shift_out,
    output reg [3:0]        bit_index
);
    integer i;
    reg [width-1:0] shift;
    reg             rx2_sampled;

    initial begin
        rec_busy    = 0;
        rec_ready   = 0;
        rec_data_h  = 0;
        shift_out   = 0;
        bit_index   = 0;
        shift       = 0;
        rx2_sampled = 1;
    end

    always @(negedge uart_rec_data_h or negedge sys_rst) begin : rx_frame
        if (!sys_rst) begin
            rec_busy   = 0;
            rec_ready  = 0;
            rec_data_h = 0;
            shift_out  = 0;
            bit_index  = 0;
            shift      = 0;
        end
        else begin
            rec_busy  = 1;
            rec_ready = 0;
            shift     = 0;
            rec_data_h = 0;

            repeat(8) @(posedge baud_op_clk);
            if (uart_rec_data_h !== 1'b0) begin
                rec_busy = 0;
                disable rx_frame;
            end

            // Wait out remainder of start bit
            repeat(8) @(posedge baud_op_clk);

            // Sample each data bit at mid-bit
            for (i = 0; i < width; i = i + 1) begin
                repeat(8) @(posedge baud_op_clk);
                rx2_sampled = uart_rec_data_h;
                shift       = {rx2_sampled, shift[width-1:1]};
                rec_data_h  = shift;
                shift_out   = shift;
                bit_index   = i;
                repeat(8) @(posedge baud_op_clk);
            end

            // Check stop bit at mid-point
            repeat(8) @(posedge baud_op_clk);
            if (uart_rec_data_h !== 1'b1) begin
                $display("[uart_rx_ref] FRAMING ERROR at time %0t", $time);
                rec_data_h = 0;
                
                // Wait out rest of stop bit then clear busy
                repeat(8) @(posedge baud_op_clk);
                rec_busy  = 0;
                rec_ready = 0;
                bit_index = 0;
                disable rx_frame;
            end

            repeat(8) @(posedge baud_op_clk);  
            rec_busy  = 0;                    

            rec_ready = 1;
            @(posedge baud_op_clk);
            rec_ready = 0;
            bit_index = 0;
        end
    end

endmodule
