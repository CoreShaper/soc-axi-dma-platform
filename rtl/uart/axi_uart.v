// =============================================================================
// AXI4-Lite UART
//
// Register map (byte addresses):
//   0x00  TX_DATA  [7:0]  – write to transmit (write-only)
//   0x04  RX_DATA  [7:0]  – received byte      (read-only)
//   0x08  STATUS   [3:0]  – {rx_full,tx_empty,rx_empty,tx_full}
//   0x0C  CTRL     [2:0]  – {loopback, rx_en, tx_en}
//   0x10  BAUD_DIV [15:0] – baud-rate divisor
//   0x14  INT_EN   [1:0]  – {rx_not_empty_ie, tx_empty_ie}
//   0x18  INT_STAT [1:0]  – {rx_not_empty, tx_empty}  (write-1-to-clear)
// =============================================================================
`timescale 1ns/1ps
module axi_uart #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter FIFO_DEPTH  = 16,
    parameter DEFAULT_DIV = 16'd868  // 50 MHz / 57600 baud ≈ 868
)(
    input  wire clk,
    input  wire rst_n,

    // UART physical pins
    input  wire uart_rx,
    output wire uart_tx,

    // Interrupt
    output wire irq,

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

localparam FIFO_PTR_W = $clog2(FIFO_DEPTH);

// ── Control registers ─────────────────────────────────────────────────────────
reg [7:0]  ctrl_reg;      // [0]=tx_en, [1]=rx_en, [2]=loopback
reg [15:0] baud_div;      // baud divisor
reg [1:0]  int_en;        // interrupt enable
reg [1:0]  int_stat;      // interrupt status (w1c)

wire tx_en    = ctrl_reg[0];
wire rx_en    = ctrl_reg[1];
wire loopback = ctrl_reg[2];

// ── TX FIFO ───────────────────────────────────────────────────────────────────
reg [7:0] tx_fifo [0:FIFO_DEPTH-1];
reg [FIFO_PTR_W:0] tx_wr_ptr, tx_rd_ptr;
wire tx_empty = (tx_wr_ptr == tx_rd_ptr);
wire tx_full  = (tx_wr_ptr[FIFO_PTR_W] != tx_rd_ptr[FIFO_PTR_W]) &&
                (tx_wr_ptr[FIFO_PTR_W-1:0] == tx_rd_ptr[FIFO_PTR_W-1:0]);

// ── RX FIFO ───────────────────────────────────────────────────────────────────
reg [7:0] rx_fifo [0:FIFO_DEPTH-1];
reg [FIFO_PTR_W:0] rx_wr_ptr, rx_rd_ptr;
wire rx_empty = (rx_wr_ptr == rx_rd_ptr);
wire rx_full  = (rx_wr_ptr[FIFO_PTR_W] != rx_rd_ptr[FIFO_PTR_W]) &&
                (rx_wr_ptr[FIFO_PTR_W-1:0] == rx_rd_ptr[FIFO_PTR_W-1:0]);

// ── Baud-rate generator ───────────────────────────────────────────────────────
// Use >= so that when baud_div is updated to a value smaller than the current
// counter, the counter resets immediately rather than waiting for overflow.
reg [15:0] baud_cnt;
reg        baud_tick;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        baud_cnt  <= 16'd0;
        baud_tick <= 1'b0;
    end else begin
        if (baud_cnt >= baud_div - 1) begin
            baud_cnt  <= 16'd0;
            baud_tick <= 1'b1;
        end else begin
            baud_cnt  <= baud_cnt + 1'b1;
            baud_tick <= 1'b0;
        end
    end
end

// ── TX shift register ─────────────────────────────────────────────────────────
localparam TX_IDLE  = 2'd0;
localparam TX_START = 2'd1;
localparam TX_DATA  = 2'd2;
localparam TX_STOP  = 2'd3;

reg [1:0] tx_state;
reg [7:0] tx_shift;
reg [3:0] tx_bit_cnt;
reg       tx_out_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_state   <= TX_IDLE;
        tx_out_r   <= 1'b1;
        tx_bit_cnt <= 4'd0;
        tx_rd_ptr  <= {(FIFO_PTR_W+1){1'b0}};
    end else if (baud_tick && tx_en) begin
        case (tx_state)
            TX_IDLE: begin
                tx_out_r <= 1'b1;
                if (!tx_empty) begin
                    tx_shift   <= tx_fifo[tx_rd_ptr[FIFO_PTR_W-1:0]];
                    tx_rd_ptr  <= tx_rd_ptr + 1'b1;
                    tx_out_r   <= 1'b0;   // start bit
                    tx_bit_cnt <= 4'd0;
                    tx_state   <= TX_DATA;
                end
            end
            TX_DATA: begin
                tx_out_r   <= tx_shift[0];
                tx_shift   <= {1'b1, tx_shift[7:1]};
                tx_bit_cnt <= tx_bit_cnt + 1'b1;
                if (tx_bit_cnt == 4'd7)
                    tx_state <= TX_STOP;
            end
            TX_STOP: begin
                tx_out_r <= 1'b1;
                tx_state <= TX_IDLE;
            end
            default: tx_state <= TX_IDLE;
        endcase
    end
end

// ── RX shift register ─────────────────────────────────────────────────────────
// 1x oversampled.  When the start bit is detected (rx_pin=0), sampling begins
// immediately on the next baud tick so that all 8 data bits are captured.
localparam RX_IDLE  = 1'b0;
localparam RX_DATA  = 1'b1;

wire rx_pin = loopback ? tx_out_r : uart_rx;

reg rx_state;
reg [7:0] rx_shift;
reg [3:0] rx_bit_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_state   <= RX_IDLE;
        rx_bit_cnt <= 4'd0;
        rx_wr_ptr  <= {(FIFO_PTR_W+1){1'b0}};
    end else if (baud_tick && rx_en) begin
        case (rx_state)
            RX_IDLE: begin
                if (!rx_pin) begin
                    // Start bit detected – begin data sampling next tick
                    rx_bit_cnt <= 4'd0;
                    rx_shift   <= 8'd0;
                    rx_state   <= RX_DATA;
                end
            end
            RX_DATA: begin
                // Shift in LSB-first; MSB of rx_shift is filled last
                rx_shift   <= {rx_pin, rx_shift[7:1]};
                rx_bit_cnt <= rx_bit_cnt + 1'b1;
                if (rx_bit_cnt == 4'd7) begin
                    // All 8 bits received; check stop bit on the next tick
                    // by temporarily reusing the IDLE state (stop bit = 1)
                    rx_state <= RX_IDLE;
                    if (!rx_full) begin
                        rx_fifo[rx_wr_ptr[FIFO_PTR_W-1:0]] <=
                            {rx_pin, rx_shift[7:1]};   // include last bit
                        rx_wr_ptr <= rx_wr_ptr + 1'b1;
                    end
                end
            end
            default: rx_state <= RX_IDLE;
        endcase
    end
end

assign uart_tx = loopback ? 1'b1 : tx_out_r;

// ── Interrupt status ──────────────────────────────────────────────────────────
wire [1:0] int_raw = {~rx_empty, tx_empty};
assign irq = |(int_en & int_raw);

// ── AXI4-Lite write handler ───────────────────────────────────────────────────
localparam WR_IDLE_S = 2'd0, WR_ADDR_S = 2'd1, WR_DATA_S = 2'd2, WR_RESP_S = 2'd3;
reg [1:0]  wr_state;
reg [ADDR_WIDTH-1:0] wr_addr_r;
reg [DATA_WIDTH-1:0] wr_data_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_state      <= WR_IDLE_S;
        s_axil_awready <= 1'b0;
        s_axil_wready  <= 1'b0;
        s_axil_bvalid  <= 1'b0;
        s_axil_bresp   <= 2'b00;
        ctrl_reg  <= 8'h03; // tx_en, rx_en default on
        baud_div  <= DEFAULT_DIV;
        int_en    <= 2'b00;
        int_stat  <= 2'b00;
        tx_wr_ptr <= {(FIFO_PTR_W+1){1'b0}};
    end else begin
        int_stat <= int_stat | int_raw; // latch interrupts

        case (wr_state)
            WR_IDLE_S: begin
                s_axil_bvalid <= 1'b0;
                if (s_axil_awvalid && s_axil_wvalid) begin
                    wr_addr_r      <= s_axil_awaddr;
                    wr_data_r      <= s_axil_wdata;
                    s_axil_awready <= 1'b1;
                    s_axil_wready  <= 1'b1;
                    wr_state       <= WR_RESP_S;
                end else if (s_axil_awvalid) begin
                    wr_addr_r      <= s_axil_awaddr;
                    s_axil_awready <= 1'b1;
                    wr_state       <= WR_DATA_S;
                end else if (s_axil_wvalid) begin
                    wr_data_r      <= s_axil_wdata;
                    s_axil_wready  <= 1'b1;
                    wr_state       <= WR_ADDR_S;
                end
            end
            WR_ADDR_S: begin
                s_axil_wready <= 1'b0;
                if (s_axil_awvalid) begin
                    wr_addr_r      <= s_axil_awaddr;
                    s_axil_awready <= 1'b1;
                    wr_state       <= WR_RESP_S;
                end
            end
            WR_DATA_S: begin
                s_axil_awready <= 1'b0;
                if (s_axil_wvalid) begin
                    wr_data_r     <= s_axil_wdata;
                    s_axil_wready <= 1'b1;
                    wr_state      <= WR_RESP_S;
                end
            end
            WR_RESP_S: begin
                s_axil_awready <= 1'b0;
                s_axil_wready  <= 1'b0;
                case (wr_addr_r[4:2])
                    3'd0: begin // TX_DATA
                        if (!tx_full) begin
                            tx_fifo[tx_wr_ptr[FIFO_PTR_W-1:0]] <= wr_data_r[7:0];
                            tx_wr_ptr <= tx_wr_ptr + 1'b1;
                        end
                    end
                    3'd2: ; // STATUS – read-only
                    3'd3: ctrl_reg <= wr_data_r[7:0];
                    3'd4: baud_div <= wr_data_r[15:0];
                    3'd5: int_en   <= wr_data_r[1:0];
                    3'd6: int_stat <= int_stat & ~wr_data_r[1:0]; // w1c
                    default: ;
                endcase
                s_axil_bresp  <= 2'b00;
                s_axil_bvalid <= 1'b1;
                if (s_axil_bready)
                    wr_state <= WR_IDLE_S;
            end
            default: wr_state <= WR_IDLE_S;
        endcase
    end
end

// ── AXI4-Lite read handler ────────────────────────────────────────────────────
localparam RD_IDLE_S = 1'b0, RD_DATA_S = 1'b1;
reg rd_state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_state      <= RD_IDLE_S;
        s_axil_arready <= 1'b0;
        s_axil_rvalid  <= 1'b0;
        s_axil_rdata   <= {DATA_WIDTH{1'b0}};
        s_axil_rresp   <= 2'b00;
        rx_rd_ptr      <= {(FIFO_PTR_W+1){1'b0}};
    end else begin
        case (rd_state)
            RD_IDLE_S: begin
                s_axil_rvalid <= 1'b0;
                if (s_axil_arvalid) begin
                    s_axil_arready <= 1'b1;
                    s_axil_rresp   <= 2'b00;
                    case (s_axil_araddr[4:2])
                        3'd0: s_axil_rdata <= {DATA_WIDTH{1'b0}}; // TX_DATA – write-only
                        3'd1: begin // RX_DATA – pop from FIFO
                            if (!rx_empty) begin
                                s_axil_rdata <= {{(DATA_WIDTH-8){1'b0}},
                                                  rx_fifo[rx_rd_ptr[FIFO_PTR_W-1:0]]};
                                rx_rd_ptr    <= rx_rd_ptr + 1'b1;
                            end else begin
                                s_axil_rdata <= {DATA_WIDTH{1'b0}};
                            end
                        end
                        3'd2: s_axil_rdata <= {{(DATA_WIDTH-4){1'b0}},
                                               rx_full, tx_empty, rx_empty, tx_full};
                        3'd3: s_axil_rdata <= {{(DATA_WIDTH-8){1'b0}}, ctrl_reg};
                        3'd4: s_axil_rdata <= {{(DATA_WIDTH-16){1'b0}}, baud_div};
                        3'd5: s_axil_rdata <= {{(DATA_WIDTH-2){1'b0}}, int_en};
                        3'd6: s_axil_rdata <= {{(DATA_WIDTH-2){1'b0}}, int_stat};
                        default: begin
                            s_axil_rdata <= {DATA_WIDTH{1'b0}};
                            s_axil_rresp <= 2'b10; // SLVERR
                        end
                    endcase
                    s_axil_rvalid <= 1'b1;
                    rd_state      <= RD_DATA_S;
                end
            end
            RD_DATA_S: begin
                s_axil_arready <= 1'b0;
                if (s_axil_rready) begin
                    s_axil_rvalid <= 1'b0;
                    rd_state      <= RD_IDLE_S;
                end
            end
            default: rd_state <= RD_IDLE_S;
        endcase
    end
end

endmodule
