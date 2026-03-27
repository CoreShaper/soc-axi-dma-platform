module top (
    input clk,
    input rst_n,
    output reg done
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        done <= 0;
    else
        done <= ~done;
end

endmodule
