// =============================================================================
// Simple CPU Core – AXI4-Lite master
//
// Instruction ROM holds a fixed program that exercises the SoC peripherals.
// Instruction format (68 bits):
//   [3:0]   opcode
//   [35:4]  address (32 bits)
//   [67:36] data    (32 bits)
//
// Opcodes:
//   NOP      (0) – do nothing for one tick
//   WRITE32  (1) – write data to address
//   READ_CHK (2) – read address, compare with data; set cpu_error on mismatch
//   WAIT_BIT (3) – poll address until (rdata & data) != 0
//   DONE     (4) – assert cpu_done and halt
// =============================================================================
`timescale 1ns/1ps
module cpu_core #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire clk,
    input  wire rst_n,

    output reg  cpu_done,
    output reg  cpu_error,

    // AXI4-Lite master
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

// ── Instruction encodings (opcode, addr, data) ────────────────────────────────
localparam NOP      = 4'd0;
localparam WRITE32  = 4'd1;
localparam READ_CHK = 4'd2;
localparam WAIT_BIT = 4'd3;
localparam DONE     = 4'd4;

// ── Program ROM ───────────────────────────────────────────────────────────────
// Encoded as {data[31:0], addr[31:0], op[3:0]} = 68 bits per instruction
// The program below:
//  1. Writes 0xDEADBEEF to RAM[0x000]
//  2. Reads  RAM[0x000] and checks == 0xDEADBEEF
//  3. Writes 0xCAFEBABE to RAM[0x004]
//  4. Reads  RAM[0x004] and checks == 0xCAFEBABE
//  5. Writes to UART TX data register (0x10000000)
//  6. Programs DMA: SRC=0x0000_0000, DST=0x0000_0100, LEN=0x10
//  7. Starts DMA (CTRL[0]=1 at 0x20000000)
//  8. Polls DMA STATUS (0x20000004) until done bit [1] is set
//  9. Reads back dst RAM[0x0100] and checks == 0xDEADBEEF
// 10. DONE

localparam PROG_DEPTH = 13;
reg [67:0] prog_rom [0:PROG_DEPTH-1];

initial begin
    // 0: Write 0xDEADBEEF -> RAM[0x000]
    prog_rom[0]  = {32'hDEAD_BEEF, 32'h0000_0000, WRITE32};
    // 1: Read RAM[0x000] and check == 0xDEADBEEF
    prog_rom[1]  = {32'hDEAD_BEEF, 32'h0000_0000, READ_CHK};
    // 2: Write 0xCAFEBABE -> RAM[0x004]
    prog_rom[2]  = {32'hCAFE_BABE, 32'h0000_0004, WRITE32};
    // 3: Read RAM[0x004] and check == 0xCAFEBABE
    prog_rom[3]  = {32'hCAFE_BABE, 32'h0000_0004, READ_CHK};
    // 4: Write 0x55 to UART TX_DATA (0x10000000)
    prog_rom[4]  = {32'h0000_0055, 32'h1000_0000, WRITE32};
    // 5: Write DMA SRC_ADDR = 0x00000000
    prog_rom[5]  = {32'h0000_0000, 32'h2000_0008, WRITE32};
    // 6: Write DMA DST_ADDR = 0x00000100
    prog_rom[6]  = {32'h0000_0100, 32'h2000_000C, WRITE32};
    // 7: Write DMA LENGTH = 0x10 (4 words)
    prog_rom[7]  = {32'h0000_0010, 32'h2000_0010, WRITE32};
    // 8: Write DMA CTRL = 1 (start)
    prog_rom[8]  = {32'h0000_0001, 32'h2000_0000, WRITE32};
    // 9: Poll DMA STATUS until done bit [1] is set
    prog_rom[9]  = {32'h0000_0002, 32'h2000_0004, WAIT_BIT};
    // 10: Read RAM[0x100] and check == 0xDEADBEEF (DMA copied it)
    prog_rom[10] = {32'hDEAD_BEEF, 32'h0000_0100, READ_CHK};
    // 11: Read RAM[0x104] and check == 0xCAFEBABE (DMA copied it)
    prog_rom[11] = {32'hCAFE_BABE, 32'h0000_0104, READ_CHK};
    // 12: DONE
    prog_rom[12] = {32'h0000_0000, 32'h0000_0000, DONE};
end

// ── CPU FSM ───────────────────────────────────────────────────────────────────
localparam CPU_FETCH   = 4'd0;
localparam CPU_WRITE_A = 4'd1;   // issue AW + W
localparam CPU_WRITE_B = 4'd2;   // wait B
localparam CPU_READ_A  = 4'd3;   // issue AR
localparam CPU_READ_B  = 4'd4;   // wait R
localparam CPU_CHK     = 4'd5;   // compare
localparam CPU_POLL_A  = 4'd6;   // poll read: issue AR
localparam CPU_POLL_B  = 4'd7;   // poll read: wait R
localparam CPU_POLL_C  = 4'd8;   // poll read: check bit set
localparam CPU_DONE    = 4'd9;

reg [3:0]  cpu_state;
reg [6:0]  pc;              // program counter
reg [67:0] ir;              // instruction register
reg [DATA_WIDTH-1:0] rd_val; // last read value

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cpu_state     <= CPU_FETCH;
        pc            <= 7'd0;
        cpu_done      <= 1'b0;
        cpu_error     <= 1'b0;
        m_axil_awvalid <= 1'b0;
        m_axil_wvalid  <= 1'b0;
        m_axil_bready  <= 1'b0;
        m_axil_arvalid <= 1'b0;
        m_axil_rready  <= 1'b0;
        m_axil_awaddr  <= {ADDR_WIDTH{1'b0}};
        m_axil_araddr  <= {ADDR_WIDTH{1'b0}};
        m_axil_wdata   <= {DATA_WIDTH{1'b0}};
        ir             <= 68'd0;
        rd_val         <= {DATA_WIDTH{1'b0}};
    end else begin
        case (cpu_state)
            CPU_FETCH: begin
                if (pc < PROG_DEPTH) begin
                    ir        <= prog_rom[pc];
                    pc        <= pc + 1'b1;
                    cpu_state <= (prog_rom[pc][3:0] == WRITE32)  ? CPU_WRITE_A :
                                 (prog_rom[pc][3:0] == READ_CHK) ? CPU_READ_A  :
                                 (prog_rom[pc][3:0] == WAIT_BIT) ? CPU_POLL_A  :
                                 (prog_rom[pc][3:0] == DONE)     ? CPU_DONE    :
                                                                    CPU_FETCH;
                end else begin
                    cpu_state <= CPU_DONE;
                end
            end

            // ── WRITE32 ───────────────────────────────────────────────────
            CPU_WRITE_A: begin
                m_axil_awaddr  <= ir[35:4];
                m_axil_awvalid <= 1'b1;
                m_axil_wdata   <= ir[67:36];
                m_axil_wvalid  <= 1'b1;
                if (m_axil_awready && m_axil_wready) begin
                    m_axil_awvalid <= 1'b0;
                    m_axil_wvalid  <= 1'b0;
                    m_axil_bready  <= 1'b1;
                    cpu_state      <= CPU_WRITE_B;
                end else if (m_axil_awready) begin
                    m_axil_awvalid <= 1'b0;
                end else if (m_axil_wready) begin
                    m_axil_wvalid <= 1'b0;
                end
            end
            CPU_WRITE_B: begin
                if (m_axil_bvalid) begin
                    m_axil_bready <= 1'b0;
                    if (m_axil_bresp != 2'b00)
                        cpu_error <= 1'b1;
                    cpu_state <= CPU_FETCH;
                end
            end

            // ── READ_CHK ──────────────────────────────────────────────────
            CPU_READ_A: begin
                m_axil_araddr  <= ir[35:4];
                m_axil_arvalid <= 1'b1;
                // Guard: only complete handshake once arvalid has been held
                // high for a full clock cycle (registered value is 1).
                if (m_axil_arvalid && m_axil_arready) begin
                    m_axil_arvalid <= 1'b0;
                    m_axil_rready  <= 1'b1;
                    cpu_state      <= CPU_READ_B;
                end
            end
            CPU_READ_B: begin
                if (m_axil_rvalid) begin
                    rd_val        <= m_axil_rdata;
                    m_axil_rready <= 1'b0;
                    if (m_axil_rresp != 2'b00)
                        cpu_error <= 1'b1;
                    cpu_state     <= CPU_CHK;
                end
            end
            CPU_CHK: begin
                if (rd_val != ir[67:36])
                    cpu_error <= 1'b1;
                cpu_state <= CPU_FETCH;
            end

            // ── WAIT_BIT (poll) ───────────────────────────────────────────
            CPU_POLL_A: begin
                m_axil_araddr  <= ir[35:4];
                m_axil_arvalid <= 1'b1;
                // Guard: only complete handshake once arvalid is registered.
                if (m_axil_arvalid && m_axil_arready) begin
                    m_axil_arvalid <= 1'b0;
                    m_axil_rready  <= 1'b1;
                    cpu_state      <= CPU_POLL_B;
                end
            end
            CPU_POLL_B: begin
                if (m_axil_rvalid) begin
                    rd_val        <= m_axil_rdata;
                    m_axil_rready <= 1'b0;
                    cpu_state     <= CPU_POLL_C;
                end
            end
            CPU_POLL_C: begin
                if ((rd_val & ir[67:36]) != {DATA_WIDTH{1'b0}}) begin
                    // Bit(s) set – continue to next instruction
                    cpu_state <= CPU_FETCH;
                end else begin
                    // Still not set – poll again
                    cpu_state <= CPU_POLL_A;
                end
            end

            // ── DONE ──────────────────────────────────────────────────────
            CPU_DONE: begin
                cpu_done  <= 1'b1;
                // Stay here
            end

            default: cpu_state <= CPU_FETCH;
        endcase
    end
end

endmodule
