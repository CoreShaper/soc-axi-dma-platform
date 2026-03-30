module top (
    input         clk,      // 时钟
    input         rst_n,    // 异步复位，低有效
    input         en,       // 累加使能
    input  [7:0]  data_in,  // 输入数据
    output [7:0]  acc,      // 累加结果
    output        carry     // 进位输出（当累加结果超过255时）
);

    // 9位加法，用于检测进位
    wire [8:0] sum = {1'b0, acc} + {1'b0, data_in};

    // 时序逻辑：累加器和进位寄存器
    reg [7:0] acc_reg;
    reg       carry_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_reg   <= 8'd0;
            carry_reg <= 1'b0;
        end else if (en) begin
            acc_reg   <= sum[7:0];   // 取低8位作为累加结果
            carry_reg <= sum[8];     // 第9位作为进位输出
        end
    end

    // 输出赋值
    assign acc   = acc_reg;
    assign carry = carry_reg;

endmodule
