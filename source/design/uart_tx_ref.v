module uart_tx_ref #(parameter width = 8)(
    input                  baud_op_clk,
    input                  sys_rst,
    input                  xmit_h,
    input  [width-1:0]     xmit_data_h,
    output reg             xmit_done_h,
    output reg             xmit_active,
    output reg             uart_xmit_data_h
);
    integer i;
    reg [width-1:0] latched_data;
    reg             busy;

    initial begin
        uart_xmit_data_h = 1;
        xmit_done_h      = 0;
        xmit_active      = 0;
        busy             = 0;
        latched_data     = 0;
    end

    // Block 1: latch data and set busy when xmit_h seen and not busy
    // Also clear xmit_done_h when new transmission starts
    always @(posedge baud_op_clk or negedge sys_rst) begin
        if (!sys_rst) begin
            latched_data <= 0;
            busy         <= 0;
            xmit_done_h  <= 0;
            xmit_active  <= 0;
        end
        else if (xmit_h && !busy) begin
            latched_data <= xmit_data_h;
            busy         <= 1;
            xmit_done_h  <= 0;   // clear done at start of new frame
            xmit_active  <= 1;
        end
    end

    // Block 2: drive serial line when busy goes high
    always @(posedge busy or negedge sys_rst) begin : tx_send
        if (!sys_rst) begin
            uart_xmit_data_h <= 1;
            xmit_done_h      <= 0;
            xmit_active      <= 0;
            busy             <= 0;
        end
        else begin
            // START bit
            @(posedge baud_op_clk);
            uart_xmit_data_h <= 0;
            repeat(15) @(posedge baud_op_clk);

            // DATA bits LSB first
            for (i = 0; i < width; i = i + 1) begin
                @(posedge baud_op_clk);
                uart_xmit_data_h <= latched_data[i];
                repeat(15) @(posedge baud_op_clk);
            end

            // STOP bit
            @(posedge baud_op_clk);
            uart_xmit_data_h <= 1;
            repeat(15) @(posedge baud_op_clk);

            // Assert done and clear active/busy
            // xmit_done_h stays HIGH (not a pulse) until next frame starts
            @(posedge baud_op_clk);
            xmit_done_h <= 1;
            xmit_active <= 0;
            busy        <= 0;
            // do NOT clear xmit_done_h here  it stays high
            // it gets cleared in Block 1 when next xmit_h arrives
        end
    end

endmodule
