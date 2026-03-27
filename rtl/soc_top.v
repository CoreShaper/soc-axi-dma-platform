// =============================================================================
// SoC Top Level
//
// Components
//   cpu_core        – AXI4-Lite master (CPU program exercises all peripherals)
//   axi_interconnect – 2M/3S AXI4-Lite crossbar with round-robin arbiter
//   axi_ram          – 16 KB data/instruction RAM  (slave 0, 0x0000_0000)
//   axi_uart         – UART with loopback option    (slave 1, 0x1000_0000)
//   dma_engine       – custom DMA controller        (slave 2, 0x2000_0000)
//
// The DMA engine's AXI4-Lite master port is wired to master port 1 of the
// interconnect so that the DMA can access RAM (and UART) autonomously while
// the CPU uses master port 0.
// =============================================================================
`timescale 1ns/1ps
module soc_top #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter RAM_DEPTH  = 4096   // 16 KB
)(
    input  wire clk,
    input  wire rst_n,

    // UART physical pins
    input  wire uart_rx,
    output wire uart_tx,

    // Interrupt lines
    output wire uart_irq,
    output wire dma_irq,

    // CPU status
    output wire cpu_done,
    output wire cpu_error
);

// ── CPU ↔ Interconnect (Master 0) ─────────────────────────────────────────────
wire [ADDR_WIDTH-1:0]   cpu_awaddr;
wire [2:0]              cpu_awprot;
wire                    cpu_awvalid;
wire                    cpu_awready;
wire [DATA_WIDTH-1:0]   cpu_wdata;
wire [DATA_WIDTH/8-1:0] cpu_wstrb;
wire                    cpu_wvalid;
wire                    cpu_wready;
wire [1:0]              cpu_bresp;
wire                    cpu_bvalid;
wire                    cpu_bready;
wire [ADDR_WIDTH-1:0]   cpu_araddr;
wire [2:0]              cpu_arprot;
wire                    cpu_arvalid;
wire                    cpu_arready;
wire [DATA_WIDTH-1:0]   cpu_rdata;
wire [1:0]              cpu_rresp;
wire                    cpu_rvalid;
wire                    cpu_rready;

// ── DMA master ↔ Interconnect (Master 1) ──────────────────────────────────────
wire [ADDR_WIDTH-1:0]   dma_m_awaddr;
wire [2:0]              dma_m_awprot;
wire                    dma_m_awvalid;
wire                    dma_m_awready;
wire [DATA_WIDTH-1:0]   dma_m_wdata;
wire [DATA_WIDTH/8-1:0] dma_m_wstrb;
wire                    dma_m_wvalid;
wire                    dma_m_wready;
wire [1:0]              dma_m_bresp;
wire                    dma_m_bvalid;
wire                    dma_m_bready;
wire [ADDR_WIDTH-1:0]   dma_m_araddr;
wire [2:0]              dma_m_arprot;
wire                    dma_m_arvalid;
wire                    dma_m_arready;
wire [DATA_WIDTH-1:0]   dma_m_rdata;
wire [1:0]              dma_m_rresp;
wire                    dma_m_rvalid;
wire                    dma_m_rready;

// ── Interconnect ↔ RAM (Slave 0) ──────────────────────────────────────────────
wire [ADDR_WIDTH-1:0]   ram_awaddr;
wire [2:0]              ram_awprot;
wire                    ram_awvalid;
wire                    ram_awready;
wire [DATA_WIDTH-1:0]   ram_wdata;
wire [DATA_WIDTH/8-1:0] ram_wstrb;
wire                    ram_wvalid;
wire                    ram_wready;
wire [1:0]              ram_bresp;
wire                    ram_bvalid;
wire                    ram_bready;
wire [ADDR_WIDTH-1:0]   ram_araddr;
wire [2:0]              ram_arprot;
wire                    ram_arvalid;
wire                    ram_arready;
wire [DATA_WIDTH-1:0]   ram_rdata;
wire [1:0]              ram_rresp;
wire                    ram_rvalid;
wire                    ram_rready;

// ── Interconnect ↔ UART (Slave 1) ─────────────────────────────────────────────
wire [ADDR_WIDTH-1:0]   uart_awaddr;
wire [2:0]              uart_awprot;
wire                    uart_awvalid;
wire                    uart_awready;
wire [DATA_WIDTH-1:0]   uart_wdata;
wire [DATA_WIDTH/8-1:0] uart_wstrb;
wire                    uart_wvalid;
wire                    uart_wready;
wire [1:0]              uart_bresp;
wire                    uart_bvalid;
wire                    uart_bready;
wire [ADDR_WIDTH-1:0]   uart_araddr;
wire [2:0]              uart_arprot;
wire                    uart_arvalid;
wire                    uart_arready;
wire [DATA_WIDTH-1:0]   uart_rdata;
wire [1:0]              uart_rresp;
wire                    uart_rvalid;
wire                    uart_rready;

// ── Interconnect ↔ DMA ctrl (Slave 2) ─────────────────────────────────────────
wire [ADDR_WIDTH-1:0]   dmac_awaddr;
wire [2:0]              dmac_awprot;
wire                    dmac_awvalid;
wire                    dmac_awready;
wire [DATA_WIDTH-1:0]   dmac_wdata;
wire [DATA_WIDTH/8-1:0] dmac_wstrb;
wire                    dmac_wvalid;
wire                    dmac_wready;
wire [1:0]              dmac_bresp;
wire                    dmac_bvalid;
wire                    dmac_bready;
wire [ADDR_WIDTH-1:0]   dmac_araddr;
wire [2:0]              dmac_arprot;
wire                    dmac_arvalid;
wire                    dmac_arready;
wire [DATA_WIDTH-1:0]   dmac_rdata;
wire [1:0]              dmac_rresp;
wire                    dmac_rvalid;
wire                    dmac_rready;

// ── Instantiations ────────────────────────────────────────────────────────────

cpu_core #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
) u_cpu (
    .clk            (clk),
    .rst_n          (rst_n),
    .cpu_done       (cpu_done),
    .cpu_error      (cpu_error),
    .m_axil_awaddr  (cpu_awaddr),
    .m_axil_awprot  (cpu_awprot),
    .m_axil_awvalid (cpu_awvalid),
    .m_axil_awready (cpu_awready),
    .m_axil_wdata   (cpu_wdata),
    .m_axil_wstrb   (cpu_wstrb),
    .m_axil_wvalid  (cpu_wvalid),
    .m_axil_wready  (cpu_wready),
    .m_axil_bresp   (cpu_bresp),
    .m_axil_bvalid  (cpu_bvalid),
    .m_axil_bready  (cpu_bready),
    .m_axil_araddr  (cpu_araddr),
    .m_axil_arprot  (cpu_arprot),
    .m_axil_arvalid (cpu_arvalid),
    .m_axil_arready (cpu_arready),
    .m_axil_rdata   (cpu_rdata),
    .m_axil_rresp   (cpu_rresp),
    .m_axil_rvalid  (cpu_rvalid),
    .m_axil_rready  (cpu_rready)
);

axi_interconnect #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
) u_interconnect (
    .clk  (clk),
    .rst_n(rst_n),
    // Master 0 – CPU
    .m0_axil_awaddr (cpu_awaddr),  .m0_axil_awprot (cpu_awprot),
    .m0_axil_awvalid(cpu_awvalid), .m0_axil_awready(cpu_awready),
    .m0_axil_wdata  (cpu_wdata),   .m0_axil_wstrb  (cpu_wstrb),
    .m0_axil_wvalid (cpu_wvalid),  .m0_axil_wready (cpu_wready),
    .m0_axil_bresp  (cpu_bresp),   .m0_axil_bvalid (cpu_bvalid),
    .m0_axil_bready (cpu_bready),
    .m0_axil_araddr (cpu_araddr),  .m0_axil_arprot (cpu_arprot),
    .m0_axil_arvalid(cpu_arvalid), .m0_axil_arready(cpu_arready),
    .m0_axil_rdata  (cpu_rdata),   .m0_axil_rresp  (cpu_rresp),
    .m0_axil_rvalid (cpu_rvalid),  .m0_axil_rready (cpu_rready),
    // Master 1 – DMA
    .m1_axil_awaddr (dma_m_awaddr),  .m1_axil_awprot (dma_m_awprot),
    .m1_axil_awvalid(dma_m_awvalid), .m1_axil_awready(dma_m_awready),
    .m1_axil_wdata  (dma_m_wdata),   .m1_axil_wstrb  (dma_m_wstrb),
    .m1_axil_wvalid (dma_m_wvalid),  .m1_axil_wready (dma_m_wready),
    .m1_axil_bresp  (dma_m_bresp),   .m1_axil_bvalid (dma_m_bvalid),
    .m1_axil_bready (dma_m_bready),
    .m1_axil_araddr (dma_m_araddr),  .m1_axil_arprot (dma_m_arprot),
    .m1_axil_arvalid(dma_m_arvalid), .m1_axil_arready(dma_m_arready),
    .m1_axil_rdata  (dma_m_rdata),   .m1_axil_rresp  (dma_m_rresp),
    .m1_axil_rvalid (dma_m_rvalid),  .m1_axil_rready (dma_m_rready),
    // Slave 0 – RAM
    .s0_axil_awaddr (ram_awaddr),  .s0_axil_awprot (ram_awprot),
    .s0_axil_awvalid(ram_awvalid), .s0_axil_awready(ram_awready),
    .s0_axil_wdata  (ram_wdata),   .s0_axil_wstrb  (ram_wstrb),
    .s0_axil_wvalid (ram_wvalid),  .s0_axil_wready (ram_wready),
    .s0_axil_bresp  (ram_bresp),   .s0_axil_bvalid (ram_bvalid),
    .s0_axil_bready (ram_bready),
    .s0_axil_araddr (ram_araddr),  .s0_axil_arprot (ram_arprot),
    .s0_axil_arvalid(ram_arvalid), .s0_axil_arready(ram_arready),
    .s0_axil_rdata  (ram_rdata),   .s0_axil_rresp  (ram_rresp),
    .s0_axil_rvalid (ram_rvalid),  .s0_axil_rready (ram_rready),
    // Slave 1 – UART
    .s1_axil_awaddr (uart_awaddr),  .s1_axil_awprot (uart_awprot),
    .s1_axil_awvalid(uart_awvalid), .s1_axil_awready(uart_awready),
    .s1_axil_wdata  (uart_wdata),   .s1_axil_wstrb  (uart_wstrb),
    .s1_axil_wvalid (uart_wvalid),  .s1_axil_wready (uart_wready),
    .s1_axil_bresp  (uart_bresp),   .s1_axil_bvalid (uart_bvalid),
    .s1_axil_bready (uart_bready),
    .s1_axil_araddr (uart_araddr),  .s1_axil_arprot (uart_arprot),
    .s1_axil_arvalid(uart_arvalid), .s1_axil_arready(uart_arready),
    .s1_axil_rdata  (uart_rdata),   .s1_axil_rresp  (uart_rresp),
    .s1_axil_rvalid (uart_rvalid),  .s1_axil_rready (uart_rready),
    // Slave 2 – DMA ctrl
    .s2_axil_awaddr (dmac_awaddr),  .s2_axil_awprot (dmac_awprot),
    .s2_axil_awvalid(dmac_awvalid), .s2_axil_awready(dmac_awready),
    .s2_axil_wdata  (dmac_wdata),   .s2_axil_wstrb  (dmac_wstrb),
    .s2_axil_wvalid (dmac_wvalid),  .s2_axil_wready (dmac_wready),
    .s2_axil_bresp  (dmac_bresp),   .s2_axil_bvalid (dmac_bvalid),
    .s2_axil_bready (dmac_bready),
    .s2_axil_araddr (dmac_araddr),  .s2_axil_arprot (dmac_arprot),
    .s2_axil_arvalid(dmac_arvalid), .s2_axil_arready(dmac_arready),
    .s2_axil_rdata  (dmac_rdata),   .s2_axil_rresp  (dmac_rresp),
    .s2_axil_rvalid (dmac_rvalid),  .s2_axil_rready (dmac_rready)
);

axi_ram #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .MEM_DEPTH (RAM_DEPTH)
) u_ram (
    .clk           (clk),
    .rst_n         (rst_n),
    .s_axil_awaddr (ram_awaddr),  .s_axil_awprot (ram_awprot),
    .s_axil_awvalid(ram_awvalid), .s_axil_awready(ram_awready),
    .s_axil_wdata  (ram_wdata),   .s_axil_wstrb  (ram_wstrb),
    .s_axil_wvalid (ram_wvalid),  .s_axil_wready (ram_wready),
    .s_axil_bresp  (ram_bresp),   .s_axil_bvalid (ram_bvalid),
    .s_axil_bready (ram_bready),
    .s_axil_araddr (ram_araddr),  .s_axil_arprot (ram_arprot),
    .s_axil_arvalid(ram_arvalid), .s_axil_arready(ram_arready),
    .s_axil_rdata  (ram_rdata),   .s_axil_rresp  (ram_rresp),
    .s_axil_rvalid (ram_rvalid),  .s_axil_rready (ram_rready)
);

axi_uart #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
) u_uart (
    .clk           (clk),
    .rst_n         (rst_n),
    .uart_rx       (uart_rx),
    .uart_tx       (uart_tx),
    .irq           (uart_irq),
    .s_axil_awaddr (uart_awaddr),  .s_axil_awprot (uart_awprot),
    .s_axil_awvalid(uart_awvalid), .s_axil_awready(uart_awready),
    .s_axil_wdata  (uart_wdata),   .s_axil_wstrb  (uart_wstrb),
    .s_axil_wvalid (uart_wvalid),  .s_axil_wready (uart_wready),
    .s_axil_bresp  (uart_bresp),   .s_axil_bvalid (uart_bvalid),
    .s_axil_bready (uart_bready),
    .s_axil_araddr (uart_araddr),  .s_axil_arprot (uart_arprot),
    .s_axil_arvalid(uart_arvalid), .s_axil_arready(uart_arready),
    .s_axil_rdata  (uart_rdata),   .s_axil_rresp  (uart_rresp),
    .s_axil_rvalid (uart_rvalid),  .s_axil_rready (uart_rready)
);

dma_engine #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
) u_dma (
    .clk           (clk),
    .rst_n         (rst_n),
    .irq           (dma_irq),
    // Ctrl slave (from interconnect slave 2)
    .s_axil_awaddr (dmac_awaddr),  .s_axil_awprot (dmac_awprot),
    .s_axil_awvalid(dmac_awvalid), .s_axil_awready(dmac_awready),
    .s_axil_wdata  (dmac_wdata),   .s_axil_wstrb  (dmac_wstrb),
    .s_axil_wvalid (dmac_wvalid),  .s_axil_wready (dmac_wready),
    .s_axil_bresp  (dmac_bresp),   .s_axil_bvalid (dmac_bvalid),
    .s_axil_bready (dmac_bready),
    .s_axil_araddr (dmac_araddr),  .s_axil_arprot (dmac_arprot),
    .s_axil_arvalid(dmac_arvalid), .s_axil_arready(dmac_arready),
    .s_axil_rdata  (dmac_rdata),   .s_axil_rresp  (dmac_rresp),
    .s_axil_rvalid (dmac_rvalid),  .s_axil_rready (dmac_rready),
    // Data master (to interconnect master 1)
    .m_axil_awaddr (dma_m_awaddr),  .m_axil_awprot (dma_m_awprot),
    .m_axil_awvalid(dma_m_awvalid), .m_axil_awready(dma_m_awready),
    .m_axil_wdata  (dma_m_wdata),   .m_axil_wstrb  (dma_m_wstrb),
    .m_axil_wvalid (dma_m_wvalid),  .m_axil_wready (dma_m_wready),
    .m_axil_bresp  (dma_m_bresp),   .m_axil_bvalid (dma_m_bvalid),
    .m_axil_bready (dma_m_bready),
    .m_axil_araddr (dma_m_araddr),  .m_axil_arprot (dma_m_arprot),
    .m_axil_arvalid(dma_m_arvalid), .m_axil_arready(dma_m_arready),
    .m_axil_rdata  (dma_m_rdata),   .m_axil_rresp  (dma_m_rresp),
    .m_axil_rvalid (dma_m_rvalid),  .m_axil_rready (dma_m_rready)
);

endmodule
