// =============================================================================
// Custom DMA Engine
//
// Control registers (AXI4-Lite slave, s_axil_*):
//   0x00  CTRL     – [0]=start, [1]=sw_reset
//   0x04  STATUS   – [0]=busy, [1]=done, [2]=error  (read-only)
//   0x08  SRC_ADDR – source start address
//   0x0C  DST_ADDR – destination start address
//   0x10  LENGTH   – transfer length in bytes (must be word-multiple)
//   0x14  INT_EN   – [0]=done_ie, [1]=error_ie
//   0x18  INT_STAT – [0]=done,    [1]=error  (write-1-to-clear)
//
// Data movement (AXI4-Lite master, m_axil_*):
//   Performs word-by-word (32-bit) memory-to-memory copies.
//
// Signal ownership:
//   CS block  : src_addr, dst_addr, length, int_en, int_stat,
//               start_req, sw_reset, s_axil_*
//   DMA FSM   : dma_state, dma_busy, dma_done, dma_error, m_axil_*
// =============================================================================
`timescale 1ns/1ps
module dma_engine #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire clk,
    input  wire rst_n,
    output wire irq,

    // AXI4-Lite slave (control)
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
    input  wire                    s_axil_rready,

    // AXI4-Lite master (data)
    output reg  [ADDR_WIDTH-1:0]   m_axil_awaddr,
    output wire [2:0]              m_axil_awprot,
    output reg                     m_axil_awvalid,
    input  wire                    m_axil_awready,
    output reg  [DATA_WIDTH-1:0]   m_axil_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axil_wstrb,
    output reg                     m_axil_wvalid,
    input  wire                    m_axil_wready,
    input  wire [1:0]              m_axil_bresp,
    input  wire                    m_axil_bvalid,
    output reg                     m_axil_bready,
    output reg  [ADDR_WIDTH-1:0]   m_axil_araddr,
    output wire [2:0]              m_axil_arprot,
    output reg                     m_axil_arvalid,
    input  wire                    m_axil_arready,
    input  wire [DATA_WIDTH-1:0]   m_axil_rdata,
    input  wire [1:0]              m_axil_rresp,
    input  wire                    m_axil_rvalid,
    output reg                     m_axil_rready
);

assign m_axil_awprot = 3'b000;
assign m_axil_arprot = 3'b000;
assign m_axil_wstrb  = {(DATA_WIDTH/8){1'b1}};

// ─── Signals owned by CS block ────────────────────────────────────────────────
reg [ADDR_WIDTH-1:0] src_addr;
reg [ADDR_WIDTH-1:0] dst_addr;
reg [31:0]           length;
reg [1:0]            int_en;
reg [1:0]            int_stat;
reg                  start_req;   // one-cycle pulse, set by CS block only
reg                  sw_reset;    // one-cycle pulse, set by CS block only

// ─── Signals owned by DMA FSM ─────────────────────────────────────────────────
reg dma_busy;
reg dma_done;
reg dma_error;

assign irq = |(int_en & {dma_error, dma_done});

// ─── DMA FSM ──────────────────────────────────────────────────────────────────
localparam DMA_IDLE    = 3'd0;
localparam DMA_RD_REQ  = 3'd1;
localparam DMA_RD_WAIT = 3'd2;
localparam DMA_WR_REQ  = 3'd3;
localparam DMA_WR_DATA = 3'd4;
localparam DMA_WR_RESP = 3'd5;
localparam DMA_NEXT    = 3'd6;
localparam DMA_DONE_ST = 3'd7;

reg [2:0]            dma_state;
reg [ADDR_WIDTH-1:0] cur_src;
reg [ADDR_WIDTH-1:0] cur_dst;
reg [31:0]           remaining;
reg [DATA_WIDTH-1:0] rd_buf;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dma_state      <= DMA_IDLE;
        dma_busy       <= 1'b0;
        dma_done       <= 1'b0;
        dma_error      <= 1'b0;
        m_axil_arvalid <= 1'b0;
        m_axil_awvalid <= 1'b0;
        m_axil_wvalid  <= 1'b0;
        m_axil_bready  <= 1'b0;
        m_axil_rready  <= 1'b0;
        m_axil_araddr  <= {ADDR_WIDTH{1'b0}};
        m_axil_awaddr  <= {ADDR_WIDTH{1'b0}};
        m_axil_wdata   <= {DATA_WIDTH{1'b0}};
        cur_src        <= {ADDR_WIDTH{1'b0}};
        cur_dst        <= {ADDR_WIDTH{1'b0}};
        remaining      <= 32'd0;
        rd_buf         <= {DATA_WIDTH{1'b0}};
    end else begin
        if (sw_reset) begin
            dma_done  <= 1'b0;
            dma_error <= 1'b0;
        end

        case (dma_state)
            DMA_IDLE: begin
                m_axil_arvalid <= 1'b0;
                m_axil_awvalid <= 1'b0;
                m_axil_wvalid  <= 1'b0;
                m_axil_bready  <= 1'b0;
                m_axil_rready  <= 1'b0;
                if (start_req) begin
                    cur_src   <= src_addr;
                    cur_dst   <= dst_addr;
                    remaining <= length >> 2;
                    dma_busy  <= 1'b1;
                    dma_done  <= 1'b0;
                    dma_error <= 1'b0;
                    if (length < 4 || length[1:0] != 2'b00) begin
                        dma_error <= 1'b1;
                        dma_busy  <= 1'b0;
                        dma_state <= DMA_DONE_ST;
                    end else
                        dma_state <= DMA_RD_REQ;
                end
            end
            DMA_RD_REQ: begin
                m_axil_araddr  <= cur_src;
                m_axil_arvalid <= 1'b1;
                // Only complete handshake when arvalid is already asserted
                // (i.e. was set in a previous cycle) so the slave sees a full
                // clock-cycle-wide arvalid pulse before we deassert it.
                if (m_axil_arvalid && m_axil_arready) begin
                    m_axil_arvalid <= 1'b0;
                    m_axil_rready  <= 1'b1;
                    dma_state      <= DMA_RD_WAIT;
                end
            end
            DMA_RD_WAIT: begin
                if (m_axil_rvalid) begin
                    rd_buf        <= m_axil_rdata;
                    m_axil_rready <= 1'b0;
                    if (m_axil_rresp != 2'b00) begin
                        dma_error <= 1'b1;
                        dma_busy  <= 1'b0;
                        dma_state <= DMA_DONE_ST;
                    end else
                        dma_state <= DMA_WR_REQ;
                end
            end
            DMA_WR_REQ: begin
                m_axil_awaddr  <= cur_dst;
                m_axil_awvalid <= 1'b1;
                // Same one-cycle rule for the AW channel.
                if (m_axil_awvalid && m_axil_awready) begin
                    m_axil_awvalid <= 1'b0;
                    m_axil_wdata   <= rd_buf;
                    m_axil_wvalid  <= 1'b1;
                    dma_state      <= DMA_WR_DATA;
                end
            end
            DMA_WR_DATA: begin
                if (m_axil_wready) begin
                    m_axil_wvalid <= 1'b0;
                    m_axil_bready <= 1'b1;
                    dma_state     <= DMA_WR_RESP;
                end
            end
            DMA_WR_RESP: begin
                if (m_axil_bvalid) begin
                    m_axil_bready <= 1'b0;
                    if (m_axil_bresp != 2'b00) begin
                        dma_error <= 1'b1;
                        dma_busy  <= 1'b0;
                        dma_state <= DMA_DONE_ST;
                    end else
                        dma_state <= DMA_NEXT;
                end
            end
            DMA_NEXT: begin
                cur_src   <= cur_src   + 4;
                cur_dst   <= cur_dst   + 4;
                remaining <= remaining - 1;
                if (remaining == 32'd1) begin
                    dma_busy  <= 1'b0;
                    dma_done  <= 1'b1;
                    dma_state <= DMA_DONE_ST;
                end else
                    dma_state <= DMA_RD_REQ;
            end
            DMA_DONE_ST: begin
                dma_state <= DMA_IDLE;
            end
            default: dma_state <= DMA_IDLE;
        endcase
    end
end

// ─── CS write handler ─────────────────────────────────────────────────────────
localparam CS_IDLE = 2'd0, CS_ADDR = 2'd1, CS_DATA = 2'd2, CS_RESP = 2'd3;
reg [1:0]            cs_wr_state;
reg [ADDR_WIDTH-1:0] cs_wr_addr;
reg [DATA_WIDTH-1:0] cs_wr_data;

// Rising-edge detectors – only latch int_stat once per pulse so W1C works.
reg dma_done_d, dma_error_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cs_wr_state    <= CS_IDLE;
        s_axil_awready <= 1'b0;
        s_axil_wready  <= 1'b0;
        s_axil_bvalid  <= 1'b0;
        s_axil_bresp   <= 2'b00;
        src_addr    <= {ADDR_WIDTH{1'b0}};
        dst_addr    <= {ADDR_WIDTH{1'b0}};
        length      <= 32'd0;
        int_en      <= 2'b00;
        int_stat    <= 2'b00;
        start_req   <= 1'b0;
        sw_reset    <= 1'b0;
        dma_done_d  <= 1'b0;
        dma_error_d <= 1'b0;
    end else begin
        // Default: deassert one-cycle pulses
        start_req <= 1'b0;
        sw_reset  <= 1'b0;

        // Capture delayed values for edge detection
        dma_done_d  <= dma_done;
        dma_error_d <= dma_error;

        // Latch int_stat only on the RISING EDGE of dma_done / dma_error so
        // that a W1C write to INT_STAT is not immediately undone while the
        // persistent dma_done/error flag remains high.
        if (dma_done  && !dma_done_d)  int_stat[0] <= 1'b1;
        if (dma_error && !dma_error_d) int_stat[1] <= 1'b1;

        case (cs_wr_state)
            CS_IDLE: begin
                s_axil_bvalid <= 1'b0;
                if (s_axil_awvalid && s_axil_wvalid) begin
                    cs_wr_addr     <= s_axil_awaddr;
                    cs_wr_data     <= s_axil_wdata;
                    s_axil_awready <= 1'b1;
                    s_axil_wready  <= 1'b1;
                    cs_wr_state    <= CS_RESP;
                end else if (s_axil_awvalid) begin
                    cs_wr_addr     <= s_axil_awaddr;
                    s_axil_awready <= 1'b1;
                    cs_wr_state    <= CS_DATA;
                end else if (s_axil_wvalid) begin
                    cs_wr_data     <= s_axil_wdata;
                    s_axil_wready  <= 1'b1;
                    cs_wr_state    <= CS_ADDR;
                end
            end
            CS_ADDR: begin
                s_axil_wready <= 1'b0;
                if (s_axil_awvalid) begin
                    cs_wr_addr     <= s_axil_awaddr;
                    s_axil_awready <= 1'b1;
                    cs_wr_state    <= CS_RESP;
                end
            end
            CS_DATA: begin
                s_axil_awready <= 1'b0;
                if (s_axil_wvalid) begin
                    cs_wr_data    <= s_axil_wdata;
                    s_axil_wready <= 1'b1;
                    cs_wr_state   <= CS_RESP;
                end
            end
            CS_RESP: begin
                s_axil_awready <= 1'b0;
                s_axil_wready  <= 1'b0;
                case (cs_wr_addr[4:2])
                    3'd0: begin
                        if (cs_wr_data[1]) sw_reset  <= 1'b1;
                        if (cs_wr_data[0] && !dma_busy) start_req <= 1'b1;
                    end
                    3'd1: ;
                    3'd2: src_addr  <= cs_wr_data;
                    3'd3: dst_addr  <= cs_wr_data;
                    3'd4: length    <= cs_wr_data;
                    3'd5: int_en    <= cs_wr_data[1:0];
                    3'd6: int_stat  <= int_stat & ~cs_wr_data[1:0];
                    default: ;
                endcase
                s_axil_bresp  <= 2'b00;
                s_axil_bvalid <= 1'b1;
                if (s_axil_bready) cs_wr_state <= CS_IDLE;
            end
            default: cs_wr_state <= CS_IDLE;
        endcase
    end
end

// ─── CS read handler ──────────────────────────────────────────────────────────
localparam CS_RD_IDLE = 1'b0, CS_RD_DATA = 1'b1;
reg cs_rd_state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cs_rd_state    <= CS_RD_IDLE;
        s_axil_arready <= 1'b0;
        s_axil_rvalid  <= 1'b0;
        s_axil_rdata   <= {DATA_WIDTH{1'b0}};
        s_axil_rresp   <= 2'b00;
    end else begin
        case (cs_rd_state)
            CS_RD_IDLE: begin
                s_axil_rvalid <= 1'b0;
                if (s_axil_arvalid) begin
                    s_axil_arready <= 1'b1;
                    s_axil_rresp   <= 2'b00;
                    case (s_axil_araddr[4:2])
                        3'd0: s_axil_rdata <= {{(DATA_WIDTH-2){1'b0}}, 1'b0, dma_busy};
                        3'd1: s_axil_rdata <= {{(DATA_WIDTH-3){1'b0}}, dma_error, dma_done, dma_busy};
                        3'd2: s_axil_rdata <= src_addr;
                        3'd3: s_axil_rdata <= dst_addr;
                        3'd4: s_axil_rdata <= length;
                        3'd5: s_axil_rdata <= {{(DATA_WIDTH-2){1'b0}}, int_en};
                        3'd6: s_axil_rdata <= {{(DATA_WIDTH-2){1'b0}}, int_stat};
                        default: begin
                            s_axil_rdata <= {DATA_WIDTH{1'b0}};
                            s_axil_rresp <= 2'b10;
                        end
                    endcase
                    s_axil_rvalid <= 1'b1;
                    cs_rd_state   <= CS_RD_DATA;
                end
            end
            CS_RD_DATA: begin
                s_axil_arready <= 1'b0;
                if (s_axil_rready) begin
                    s_axil_rvalid <= 1'b0;
                    cs_rd_state   <= CS_RD_IDLE;
                end
            end
            default: cs_rd_state <= CS_RD_IDLE;
        endcase
    end
end

endmodule
