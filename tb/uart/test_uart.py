"""
AXI-UART unit test (cocotb)
Exercises register access, loopback TX→RX, and interrupt status.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotbext.axi import AxiLiteBus, AxiLiteMaster
import struct

# UART register offsets
TX_DATA  = 0x00
RX_DATA  = 0x04
STATUS   = 0x08
CTRL     = 0x0C
BAUD_DIV = 0x10
INT_EN   = 0x14
INT_STAT = 0x18

# STATUS bits
TX_FULL  = 0x01
RX_EMPTY = 0x02
TX_EMPTY = 0x04

# CTRL bits
TX_EN    = 0x01
RX_EN    = 0x02
LOOPBACK = 0x04


async def reset_dut(dut, cycles=10):
    dut.rst_n.value = 0
    dut.uart_rx.value = 1      # idle high
    await ClockCycles(dut.clk, cycles)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def test_ctrl_register(dut):
    """Read-back the CTRL register after writing."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst_n,
                         reset_active_level=False)

    await axil.write(CTRL, struct.pack("<I", TX_EN | RX_EN | LOOPBACK))
    rd = await axil.read(CTRL, 4)
    val = struct.unpack("<I", rd.data)[0] & 0x07
    assert val == (TX_EN | RX_EN | LOOPBACK), f"CTRL mismatch: 0x{val:02X}"


@cocotb.test()
async def test_baud_div_register(dut):
    """Write and read back BAUD_DIV."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst_n,
                         reset_active_level=False)

    await axil.write(BAUD_DIV, struct.pack("<I", 0x0064))   # divisor = 100
    rd = await axil.read(BAUD_DIV, 4)
    val = struct.unpack("<I", rd.data)[0] & 0xFFFF
    assert val == 0x0064, f"BAUD_DIV mismatch: 0x{val:04X}"


@cocotb.test()
async def test_status_initial(dut):
    """After reset the TX FIFO is empty, RX FIFO is empty."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst_n,
                         reset_active_level=False)

    rd = await axil.read(STATUS, 4)
    status = struct.unpack("<I", rd.data)[0] & 0x0F
    assert status & TX_EMPTY, "TX FIFO should be empty after reset"
    assert status & RX_EMPTY, "RX FIFO should be empty after reset"
    assert not (status & TX_FULL), "TX FIFO should not be full after reset"


@cocotb.test()
async def test_loopback_byte(dut):
    """Write a byte in loopback mode and read it back from RX_DATA.

    In loopback mode the TX serialiser output is internally fed back to the
    RX deserialiser.  With the default baud divisor reduced to a small value
    the loop completes in a reasonable simulation time.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst_n,
                         reset_active_level=False)

    # Use a very small baud divisor so the UART bit-time is only 4 clock ticks
    await axil.write(BAUD_DIV, struct.pack("<I", 4))
    # Enable TX, RX, and loopback
    await axil.write(CTRL, struct.pack("<I", TX_EN | RX_EN | LOOPBACK))

    # Transmit 0xA5
    await axil.write(TX_DATA, struct.pack("<I", 0xA5))

    # Wait long enough for one complete UART frame at divisor=4
    # Frame = 1 start + 8 data + 1 stop = 10 bit-times = 10 * 4 = 40 clocks
    # Add some margin
    await ClockCycles(dut.clk, 200)

    # RX FIFO should no longer be empty
    rd = await axil.read(STATUS, 4)
    status = struct.unpack("<I", rd.data)[0] & 0x0F
    assert not (status & RX_EMPTY), "RX FIFO should not be empty after loopback"

    # Read the received byte
    rd = await axil.read(RX_DATA, 4)
    rx_byte = struct.unpack("<I", rd.data)[0] & 0xFF
    assert rx_byte == 0xA5, f"Loopback byte mismatch: expected 0xA5, got 0x{rx_byte:02X}"


@cocotb.test()
async def test_interrupt_enable_tx_empty(dut):
    """Enabling the TX-empty interrupt should raise IRQ when TX FIFO is empty."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst_n,
                         reset_active_level=False)

    # Enable TX-empty interrupt (bit 0)
    await axil.write(INT_EN, struct.pack("<I", 0x01))
    await ClockCycles(dut.clk, 2)

    # IRQ should be high because TX FIFO starts empty
    assert dut.irq.value == 1, "IRQ should be asserted when TX FIFO is empty and tx_empty_ie is set"

    # Disable interrupt
    await axil.write(INT_EN, struct.pack("<I", 0x00))
    await ClockCycles(dut.clk, 2)
    assert dut.irq.value == 0, "IRQ should be deasserted after disabling interrupt"
