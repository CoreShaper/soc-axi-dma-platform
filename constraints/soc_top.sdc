# =============================================================================
# Basic STA Constraints – SoC AXI-DMA Platform
# Target: 100 MHz (10 ns period)
# =============================================================================

# ── Clock definition ──────────────────────────────────────────────────────────
create_clock -name clk -period 10.0 [get_ports clk]

# ── Clock uncertainty & transition ───────────────────────────────────────────
set_clock_uncertainty 0.15 [get_clocks clk]
set_clock_transition  0.10 [get_clocks clk]

# ── Input / output delays ─────────────────────────────────────────────────────
# Assume external I/O paths with 2 ns setup / 1 ns hold margins.
set_input_delay  -clock clk -max 2.0 [get_ports {rst_n uart_rx}]
set_input_delay  -clock clk -min 0.5 [get_ports {rst_n uart_rx}]

set_output_delay -clock clk -max 2.0 [get_ports {uart_tx uart_irq dma_irq cpu_done cpu_error}]
set_output_delay -clock clk -min 0.5 [get_ports {uart_tx uart_irq dma_irq cpu_done cpu_error}]

# ── False paths ───────────────────────────────────────────────────────────────
# Asynchronous reset is a false path for timing analysis
set_false_path -from [get_ports rst_n]

# ── Multi-cycle paths ─────────────────────────────────────────────────────────
# The CPU instruction ROM is registered and does not change mid-flight.
# Allow 2 cycles for any path through the ROM decode.
set_multicycle_path -setup 2 -from [get_cells u_cpu/prog_rom*]
set_multicycle_path -hold  1 -from [get_cells u_cpu/prog_rom*]

# ── Max fanout / capacitance ──────────────────────────────────────────────────
set_max_fanout 16 [current_design]
set_max_capacitance 0.5 [current_design]

# ── Area / power hints ────────────────────────────────────────────────────────
set_driving_cell -lib_cell BUF_X1 [get_ports {clk rst_n uart_rx}]
set_load 0.05 [get_ports {uart_tx uart_irq dma_irq cpu_done cpu_error}]
