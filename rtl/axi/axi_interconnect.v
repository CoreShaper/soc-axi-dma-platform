// =============================================================================
// AXI4-Lite Interconnect – 2 Masters / 3 Slaves
// Master 0 : CPU
// Master 1 : DMA data port
// Slave  0 : RAM   (0x0000_0000 – 0x0000_FFFF)
// Slave  1 : UART  (0x1000_0000 – 0x1000_00FF)
// Slave  2 : DMA control (0x2000_0000 – 0x2000_00FF)
// =============================================================================
`timescale 1ns/1ps
module axi_interconnect #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    // Slave address base / mask
    parameter [ADDR_WIDTH-1:0] S0_BASE = 32'h0000_0000,
    parameter [ADDR_WIDTH-1:0] S0_MASK = 32'hFFFF_0000,
    parameter [ADDR_WIDTH-1:0] S1_BASE = 32'h1000_0000,
    parameter [ADDR_WIDTH-1:0] S1_MASK = 32'hFFFF_FF00,
    parameter [ADDR_WIDTH-1:0] S2_BASE = 32'h2000_0000,
    parameter [ADDR_WIDTH-1:0] S2_MASK = 32'hFFFF_FF00
)(
    input  wire clk,
    input  wire rst_n,

    // ── Master 0 (CPU) ──────────────────────────────────────────────────────
    input  wire [ADDR_WIDTH-1:0] m0_axil_awaddr,
    input  wire [2:0]            m0_axil_awprot,
    input  wire                  m0_axil_awvalid,
    output wire                  m0_axil_awready,

    input  wire [DATA_WIDTH-1:0]   m0_axil_wdata,
    input  wire [DATA_WIDTH/8-1:0] m0_axil_wstrb,
    input  wire                    m0_axil_wvalid,
    output wire                    m0_axil_wready,

    output wire [1:0]            m0_axil_bresp,
    output wire                  m0_axil_bvalid,
    input  wire                  m0_axil_bready,

    input  wire [ADDR_WIDTH-1:0] m0_axil_araddr,
    input  wire [2:0]            m0_axil_arprot,
    input  wire                  m0_axil_arvalid,
    output wire                  m0_axil_arready,

    output wire [DATA_WIDTH-1:0] m0_axil_rdata,
    output wire [1:0]            m0_axil_rresp,
    output wire                  m0_axil_rvalid,
    input  wire                  m0_axil_rready,

    // ── Master 1 (DMA) ──────────────────────────────────────────────────────
    input  wire [ADDR_WIDTH-1:0] m1_axil_awaddr,
    input  wire [2:0]            m1_axil_awprot,
    input  wire                  m1_axil_awvalid,
    output wire                  m1_axil_awready,

    input  wire [DATA_WIDTH-1:0]   m1_axil_wdata,
    input  wire [DATA_WIDTH/8-1:0] m1_axil_wstrb,
    input  wire                    m1_axil_wvalid,
    output wire                    m1_axil_wready,

    output wire [1:0]            m1_axil_bresp,
    output wire                  m1_axil_bvalid,
    input  wire                  m1_axil_bready,

    input  wire [ADDR_WIDTH-1:0] m1_axil_araddr,
    input  wire [2:0]            m1_axil_arprot,
    input  wire                  m1_axil_arvalid,
    output wire                  m1_axil_arready,

    output wire [DATA_WIDTH-1:0] m1_axil_rdata,
    output wire [1:0]            m1_axil_rresp,
    output wire                  m1_axil_rvalid,
    input  wire                  m1_axil_rready,

    // ── Slave 0 (RAM) ────────────────────────────────────────────────────────
    output wire [ADDR_WIDTH-1:0] s0_axil_awaddr,
    output wire [2:0]            s0_axil_awprot,
    output wire                  s0_axil_awvalid,
    input  wire                  s0_axil_awready,

    output wire [DATA_WIDTH-1:0]   s0_axil_wdata,
    output wire [DATA_WIDTH/8-1:0] s0_axil_wstrb,
    output wire                    s0_axil_wvalid,
    input  wire                    s0_axil_wready,

    input  wire [1:0]            s0_axil_bresp,
    input  wire                  s0_axil_bvalid,
    output wire                  s0_axil_bready,

    output wire [ADDR_WIDTH-1:0] s0_axil_araddr,
    output wire [2:0]            s0_axil_arprot,
    output wire                  s0_axil_arvalid,
    input  wire                  s0_axil_arready,

    input  wire [DATA_WIDTH-1:0] s0_axil_rdata,
    input  wire [1:0]            s0_axil_rresp,
    input  wire                  s0_axil_rvalid,
    output wire                  s0_axil_rready,

    // ── Slave 1 (UART) ───────────────────────────────────────────────────────
    output wire [ADDR_WIDTH-1:0] s1_axil_awaddr,
    output wire [2:0]            s1_axil_awprot,
    output wire                  s1_axil_awvalid,
    input  wire                  s1_axil_awready,

    output wire [DATA_WIDTH-1:0]   s1_axil_wdata,
    output wire [DATA_WIDTH/8-1:0] s1_axil_wstrb,
    output wire                    s1_axil_wvalid,
    input  wire                    s1_axil_wready,

    input  wire [1:0]            s1_axil_bresp,
    input  wire                  s1_axil_bvalid,
    output wire                  s1_axil_bready,

    output wire [ADDR_WIDTH-1:0] s1_axil_araddr,
    output wire [2:0]            s1_axil_arprot,
    output wire                  s1_axil_arvalid,
    input  wire                  s1_axil_arready,

    input  wire [DATA_WIDTH-1:0] s1_axil_rdata,
    input  wire [1:0]            s1_axil_rresp,
    input  wire                  s1_axil_rvalid,
    output wire                  s1_axil_rready,

    // ── Slave 2 (DMA ctrl) ───────────────────────────────────────────────────
    output wire [ADDR_WIDTH-1:0] s2_axil_awaddr,
    output wire [2:0]            s2_axil_awprot,
    output wire                  s2_axil_awvalid,
    input  wire                  s2_axil_awready,

    output wire [DATA_WIDTH-1:0]   s2_axil_wdata,
    output wire [DATA_WIDTH/8-1:0] s2_axil_wstrb,
    output wire                    s2_axil_wvalid,
    input  wire                    s2_axil_wready,

    input  wire [1:0]            s2_axil_bresp,
    input  wire                  s2_axil_bvalid,
    output wire                  s2_axil_bready,

    output wire [ADDR_WIDTH-1:0] s2_axil_araddr,
    output wire [2:0]            s2_axil_arprot,
    output wire                  s2_axil_arvalid,
    input  wire                  s2_axil_arready,

    input  wire [DATA_WIDTH-1:0] s2_axil_rdata,
    input  wire [1:0]            s2_axil_rresp,
    input  wire                  s2_axil_rvalid,
    output wire                  s2_axil_rready
);

// ---------------------------------------------------------------------------
// Address decode function
// Returns 2-bit slave index (3 = decode error → no slave)
// ---------------------------------------------------------------------------
// Address decode: (addr & MASK) == BASE selects which upper address bits must
// match.  S0_MASK=0xFFFF0000 means bits [31:16] are compared against BASE.
function [1:0] decode_slave;
    input [ADDR_WIDTH-1:0] addr;
    begin
        if ((addr & S0_MASK) == S0_BASE)
            decode_slave = 2'd0;
        else if ((addr & S1_MASK) == S1_BASE)
            decode_slave = 2'd1;
        else if ((addr & S2_MASK) == S2_BASE)
            decode_slave = 2'd2;
        else
            decode_slave = 2'd3; // decode error
    end
endfunction

// ---------------------------------------------------------------------------
// Write-channel arbitration (AW + W + B)
// State: IDLE → grant master → wait for B response
// ---------------------------------------------------------------------------
localparam WR_IDLE  = 2'd0;
localparam WR_M0    = 2'd1;  // Master 0 owns the write bus
localparam WR_M1    = 2'd2;  // Master 1 owns the write bus

reg [1:0] wr_state;
reg [1:0] wr_slave;   // selected slave for current write txn
reg       wr_rr;      // round-robin toggle (last winner)

// Qualified request signals
wire wr_req_m0 = m0_axil_awvalid;
wire wr_req_m1 = m1_axil_awvalid;

// Current granted master address / control
wire [ADDR_WIDTH-1:0] wr_addr_granted = (wr_state == WR_M0) ? m0_axil_awaddr : m1_axil_awaddr;
wire [2:0]            wr_prot_granted = (wr_state == WR_M0) ? m0_axil_awprot : m1_axil_awprot;
wire [DATA_WIDTH-1:0]   wr_data_granted = (wr_state == WR_M0) ? m0_axil_wdata  : m1_axil_wdata;
wire [DATA_WIDTH/8-1:0] wr_strb_granted = (wr_state == WR_M0) ? m0_axil_wstrb  : m1_axil_wstrb;
wire                    wr_wvalid_granted = (wr_state == WR_M0) ? m0_axil_wvalid : m1_axil_wvalid;

// Slave mux for write channels
wire s_awready_sel = (wr_slave == 2'd0) ? s0_axil_awready :
                     (wr_slave == 2'd1) ? s1_axil_awready :
                     (wr_slave == 2'd2) ? s2_axil_awready : 1'b1;

wire s_wready_sel  = (wr_slave == 2'd0) ? s0_axil_wready  :
                     (wr_slave == 2'd1) ? s1_axil_wready  :
                     (wr_slave == 2'd2) ? s2_axil_wready  : 1'b1;

wire [1:0] s_bresp_sel  = (wr_slave == 2'd0) ? s0_axil_bresp  :
                          (wr_slave == 2'd1) ? s1_axil_bresp  :
                          (wr_slave == 2'd2) ? s2_axil_bresp  : 2'b10;

wire s_bvalid_sel  = (wr_slave == 2'd0) ? s0_axil_bvalid  :
                     (wr_slave == 2'd1) ? s1_axil_bvalid  :
                     (wr_slave == 2'd2) ? s2_axil_bvalid  : 1'b1;

// Master bready selection
wire m_bready_granted = (wr_state == WR_M0) ? m0_axil_bready : m1_axil_bready;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_state <= WR_IDLE;
        wr_slave <= 2'd0;
        wr_rr    <= 1'b0;
    end else begin
        case (wr_state)
            WR_IDLE: begin
                if (wr_req_m0 && wr_req_m1) begin
                    // Both requesting – round-robin
                    if (!wr_rr) begin
                        wr_state <= WR_M0;
                        wr_slave <= decode_slave(m0_axil_awaddr);
                        wr_rr    <= 1'b1;
                    end else begin
                        wr_state <= WR_M1;
                        wr_slave <= decode_slave(m1_axil_awaddr);
                        wr_rr    <= 1'b0;
                    end
                end else if (wr_req_m0) begin
                    wr_state <= WR_M0;
                    wr_slave <= decode_slave(m0_axil_awaddr);
                end else if (wr_req_m1) begin
                    wr_state <= WR_M1;
                    wr_slave <= decode_slave(m1_axil_awaddr);
                end
            end
            WR_M0, WR_M1: begin
                // Release when B response completes
                if (s_bvalid_sel && m_bready_granted)
                    wr_state <= WR_IDLE;
            end
            default: wr_state <= WR_IDLE;
        endcase
    end
end

// ---------------------------------------------------------------------------
// Read-channel arbitration (AR + R)
// ---------------------------------------------------------------------------
localparam RD_IDLE  = 2'd0;
localparam RD_M0    = 2'd1;
localparam RD_M1    = 2'd2;

reg [1:0] rd_state;
reg [1:0] rd_slave;
reg       rd_rr;

wire rd_req_m0 = m0_axil_arvalid;
wire rd_req_m1 = m1_axil_arvalid;

wire [ADDR_WIDTH-1:0] rd_addr_granted = (rd_state == RD_M0) ? m0_axil_araddr : m1_axil_araddr;
wire [2:0]            rd_prot_granted = (rd_state == RD_M0) ? m0_axil_arprot : m1_axil_arprot;

wire s_arready_sel = (rd_slave == 2'd0) ? s0_axil_arready :
                     (rd_slave == 2'd1) ? s1_axil_arready :
                     (rd_slave == 2'd2) ? s2_axil_arready : 1'b1;

wire [DATA_WIDTH-1:0] s_rdata_sel  = (rd_slave == 2'd0) ? s0_axil_rdata  :
                                     (rd_slave == 2'd1) ? s1_axil_rdata  :
                                     (rd_slave == 2'd2) ? s2_axil_rdata  : {DATA_WIDTH{1'b0}};

wire [1:0] s_rresp_sel  = (rd_slave == 2'd0) ? s0_axil_rresp  :
                          (rd_slave == 2'd1) ? s1_axil_rresp  :
                          (rd_slave == 2'd2) ? s2_axil_rresp  : 2'b10;

wire s_rvalid_sel  = (rd_slave == 2'd0) ? s0_axil_rvalid  :
                     (rd_slave == 2'd1) ? s1_axil_rvalid  :
                     (rd_slave == 2'd2) ? s2_axil_rvalid  : 1'b1;

wire m_rready_granted = (rd_state == RD_M0) ? m0_axil_rready : m1_axil_rready;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_state <= RD_IDLE;
        rd_slave <= 2'd0;
        rd_rr    <= 1'b0;
    end else begin
        case (rd_state)
            RD_IDLE: begin
                if (rd_req_m0 && rd_req_m1) begin
                    if (!rd_rr) begin
                        rd_state <= RD_M0;
                        rd_slave <= decode_slave(m0_axil_araddr);
                        rd_rr    <= 1'b1;
                    end else begin
                        rd_state <= RD_M1;
                        rd_slave <= decode_slave(m1_axil_araddr);
                        rd_rr    <= 1'b0;
                    end
                end else if (rd_req_m0) begin
                    rd_state <= RD_M0;
                    rd_slave <= decode_slave(m0_axil_araddr);
                end else if (rd_req_m1) begin
                    rd_state <= RD_M1;
                    rd_slave <= decode_slave(m1_axil_araddr);
                end
            end
            RD_M0, RD_M1: begin
                if (s_rvalid_sel && m_rready_granted)
                    rd_state <= RD_IDLE;
            end
            default: rd_state <= RD_IDLE;
        endcase
    end
end

// ---------------------------------------------------------------------------
// Write channel output mux
// ---------------------------------------------------------------------------
// AW to slaves
assign s0_axil_awvalid = (wr_state == WR_M0 || wr_state == WR_M1) && (wr_slave == 2'd0) ? 1'b1 : 1'b0;
assign s1_axil_awvalid = (wr_state == WR_M0 || wr_state == WR_M1) && (wr_slave == 2'd1) ? 1'b1 : 1'b0;
assign s2_axil_awvalid = (wr_state == WR_M0 || wr_state == WR_M1) && (wr_slave == 2'd2) ? 1'b1 : 1'b0;

assign s0_axil_awaddr  = wr_addr_granted;
assign s1_axil_awaddr  = wr_addr_granted;
assign s2_axil_awaddr  = wr_addr_granted;
assign s0_axil_awprot  = wr_prot_granted;
assign s1_axil_awprot  = wr_prot_granted;
assign s2_axil_awprot  = wr_prot_granted;

// AW ready to masters
assign m0_axil_awready = (wr_state == WR_M0) ? s_awready_sel : 1'b0;
assign m1_axil_awready = (wr_state == WR_M1) ? s_awready_sel : 1'b0;

// W to slaves
wire wr_active = (wr_state == WR_M0 || wr_state == WR_M1);
assign s0_axil_wvalid = wr_active && (wr_slave == 2'd0) ? wr_wvalid_granted : 1'b0;
assign s1_axil_wvalid = wr_active && (wr_slave == 2'd1) ? wr_wvalid_granted : 1'b0;
assign s2_axil_wvalid = wr_active && (wr_slave == 2'd2) ? wr_wvalid_granted : 1'b0;

assign s0_axil_wdata  = wr_data_granted;
assign s1_axil_wdata  = wr_data_granted;
assign s2_axil_wdata  = wr_data_granted;
assign s0_axil_wstrb  = wr_strb_granted;
assign s1_axil_wstrb  = wr_strb_granted;
assign s2_axil_wstrb  = wr_strb_granted;

// W ready to masters
assign m0_axil_wready = (wr_state == WR_M0) ? s_wready_sel : 1'b0;
assign m1_axil_wready = (wr_state == WR_M1) ? s_wready_sel : 1'b0;

// B to masters
assign m0_axil_bresp  = (wr_state == WR_M0) ? s_bresp_sel  : 2'b00;
assign m1_axil_bresp  = (wr_state == WR_M1) ? s_bresp_sel  : 2'b00;
assign m0_axil_bvalid = (wr_state == WR_M0) ? s_bvalid_sel : 1'b0;
assign m1_axil_bvalid = (wr_state == WR_M1) ? s_bvalid_sel : 1'b0;

// B ready to slaves
assign s0_axil_bready = wr_active && (wr_slave == 2'd0) ? m_bready_granted : 1'b0;
assign s1_axil_bready = wr_active && (wr_slave == 2'd1) ? m_bready_granted : 1'b0;
assign s2_axil_bready = wr_active && (wr_slave == 2'd2) ? m_bready_granted : 1'b0;

// ---------------------------------------------------------------------------
// Read channel output mux
// ---------------------------------------------------------------------------
wire rd_active = (rd_state == RD_M0 || rd_state == RD_M1);

assign s0_axil_arvalid = rd_active && (rd_slave == 2'd0) ? 1'b1 : 1'b0;
assign s1_axil_arvalid = rd_active && (rd_slave == 2'd1) ? 1'b1 : 1'b0;
assign s2_axil_arvalid = rd_active && (rd_slave == 2'd2) ? 1'b1 : 1'b0;

assign s0_axil_araddr  = rd_addr_granted;
assign s1_axil_araddr  = rd_addr_granted;
assign s2_axil_araddr  = rd_addr_granted;
assign s0_axil_arprot  = rd_prot_granted;
assign s1_axil_arprot  = rd_prot_granted;
assign s2_axil_arprot  = rd_prot_granted;

// AR ready to masters
assign m0_axil_arready = (rd_state == RD_M0) ? s_arready_sel : 1'b0;
assign m1_axil_arready = (rd_state == RD_M1) ? s_arready_sel : 1'b0;

// R to masters
assign m0_axil_rdata  = (rd_state == RD_M0) ? s_rdata_sel  : {DATA_WIDTH{1'b0}};
assign m1_axil_rdata  = (rd_state == RD_M1) ? s_rdata_sel  : {DATA_WIDTH{1'b0}};
assign m0_axil_rresp  = (rd_state == RD_M0) ? s_rresp_sel  : 2'b00;
assign m1_axil_rresp  = (rd_state == RD_M1) ? s_rresp_sel  : 2'b00;
assign m0_axil_rvalid = (rd_state == RD_M0) ? s_rvalid_sel : 1'b0;
assign m1_axil_rvalid = (rd_state == RD_M1) ? s_rvalid_sel : 1'b0;

// R ready to slaves
assign s0_axil_rready = rd_active && (rd_slave == 2'd0) ? m_rready_granted : 1'b0;
assign s1_axil_rready = rd_active && (rd_slave == 2'd1) ? m_rready_granted : 1'b0;
assign s2_axil_rready = rd_active && (rd_slave == 2'd2) ? m_rready_granted : 1'b0;

endmodule
