// =============================================================================
// AXI4-Lite RAM
// Parameters : DATA_WIDTH = 32, MEM_DEPTH = 4096 (16 KB)
// =============================================================================
`timescale 1ns/1ps
module axi_ram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter MEM_DEPTH  = 4096   // words
)(
    input  wire clk,
    input  wire rst_n,

    // AXI4-Lite slave
    input  wire [ADDR_WIDTH-1:0]   s_axil_awaddr,
    input  wire [2:0]              s_axil_awprot,
    input  wire                    s_axil_awvalid,
    output reg                     s_axil_awready,

    input  wire [DATA_WIDTH-1:0]   s_axil_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axil_wstrb,
    input  wire                    s_axil_wvalid,
    output reg                     s_axil_wready,

    output reg  [1:0]              s_axil_bresp,
    output reg                     s_axil_bvalid,
    input  wire                    s_axil_bready,

    input  wire [ADDR_WIDTH-1:0]   s_axil_araddr,
    input  wire [2:0]              s_axil_arprot,
    input  wire                    s_axil_arvalid,
    output reg                     s_axil_arready,

    output reg  [DATA_WIDTH-1:0]   s_axil_rdata,
    output reg  [1:0]              s_axil_rresp,
    output reg                     s_axil_rvalid,
    input  wire                    s_axil_rready
);

localparam ADDR_LSB = $clog2(DATA_WIDTH/8);

// ── Memory array ─────────────────────────────────────────────────────────────
reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

integer i;
initial begin
    for (i = 0; i < MEM_DEPTH; i = i + 1)
        mem[i] = {DATA_WIDTH{1'b0}};
end

// ── Write state machine ───────────────────────────────────────────────────────
localparam WR_IDLE = 2'd0, WR_ADDR = 2'd1, WR_DATA = 2'd2, WR_RESP = 2'd3;
reg [1:0] wr_state;
reg [ADDR_WIDTH-1:0] wr_addr_r;
reg [DATA_WIDTH-1:0] wr_data_r;
reg [DATA_WIDTH/8-1:0] wr_strb_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_state      <= WR_IDLE;
        s_axil_awready <= 1'b0;
        s_axil_wready  <= 1'b0;
        s_axil_bvalid  <= 1'b0;
        s_axil_bresp   <= 2'b00;
        wr_addr_r      <= {ADDR_WIDTH{1'b0}};
    end else begin
        case (wr_state)
            WR_IDLE: begin
                s_axil_bvalid <= 1'b0;
                if (s_axil_awvalid && s_axil_wvalid) begin
                    // Accept both address and data in same cycle
                    wr_addr_r      <= s_axil_awaddr;
                    wr_data_r      <= s_axil_wdata;
                    wr_strb_r      <= s_axil_wstrb;
                    s_axil_awready <= 1'b1;
                    s_axil_wready  <= 1'b1;
                    wr_state       <= WR_RESP;
                end else if (s_axil_awvalid) begin
                    wr_addr_r      <= s_axil_awaddr;
                    s_axil_awready <= 1'b1;
                    wr_state       <= WR_DATA;
                end else if (s_axil_wvalid) begin
                    wr_data_r      <= s_axil_wdata;
                    wr_strb_r      <= s_axil_wstrb;
                    s_axil_wready  <= 1'b1;
                    wr_state       <= WR_ADDR;
                end
            end
            WR_ADDR: begin
                // Waiting for AW
                s_axil_wready <= 1'b0;
                if (s_axil_awvalid) begin
                    wr_addr_r      <= s_axil_awaddr;
                    s_axil_awready <= 1'b1;
                    wr_state       <= WR_RESP;
                end
            end
            WR_DATA: begin
                // Waiting for W
                s_axil_awready <= 1'b0;
                if (s_axil_wvalid) begin
                    wr_data_r     <= s_axil_wdata;
                    wr_strb_r     <= s_axil_wstrb;
                    s_axil_wready <= 1'b1;
                    wr_state      <= WR_RESP;
                end
            end
            WR_RESP: begin
                s_axil_awready <= 1'b0;
                s_axil_wready  <= 1'b0;
                // Perform write
                begin : do_write
                    integer j;
                    reg [ADDR_WIDTH-1:0] word_addr;
                    word_addr = wr_addr_r >> ADDR_LSB;
                    if (word_addr < MEM_DEPTH) begin
                        for (j = 0; j < DATA_WIDTH/8; j = j + 1) begin
                            if (wr_strb_r[j])
                                mem[word_addr][j*8 +: 8] <= wr_data_r[j*8 +: 8];
                        end
                        s_axil_bresp <= 2'b00; // OKAY
                    end else begin
                        s_axil_bresp <= 2'b10; // SLVERR
                    end
                end
                s_axil_bvalid <= 1'b1;
                if (s_axil_bready)
                    wr_state <= WR_IDLE;
            end
            default: wr_state <= WR_IDLE;
        endcase
    end
end

// ── Read state machine ────────────────────────────────────────────────────────
localparam RD_IDLE = 1'b0, RD_DATA = 1'b1;
reg rd_state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_state      <= RD_IDLE;
        s_axil_arready <= 1'b0;
        s_axil_rvalid  <= 1'b0;
        s_axil_rdata   <= {DATA_WIDTH{1'b0}};
        s_axil_rresp   <= 2'b00;
    end else begin
        case (rd_state)
            RD_IDLE: begin
                s_axil_rvalid <= 1'b0;
                if (s_axil_arvalid) begin
                    begin : do_read
                        reg [ADDR_WIDTH-1:0] word_addr;
                        word_addr = s_axil_araddr >> ADDR_LSB;
                        if (word_addr < MEM_DEPTH) begin
                            s_axil_rdata <= mem[word_addr];
                            s_axil_rresp <= 2'b00;
                        end else begin
                            s_axil_rdata <= {DATA_WIDTH{1'b0}};
                            s_axil_rresp <= 2'b10; // SLVERR
                        end
                    end
                    s_axil_arready <= 1'b1;
                    s_axil_rvalid  <= 1'b1;
                    rd_state       <= RD_DATA;
                end
            end
            RD_DATA: begin
                s_axil_arready <= 1'b0;
                if (s_axil_rready) begin
                    s_axil_rvalid <= 1'b0;
                    rd_state      <= RD_IDLE;
                end
            end
            default: rd_state <= RD_IDLE;
        endcase
    end
end

endmodule
