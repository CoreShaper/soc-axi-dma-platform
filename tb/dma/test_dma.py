"""
DMA Engine unit test (cocotb)
Uses AxiLiteMaster for the DMA control slave and AxiLiteRam as the memory
model that satisfies the DMA's AXI4-Lite master transactions.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer, with_timeout
from cocotbext.axi import AxiLiteBus, AxiLiteMaster, AxiLiteRam
import struct

# DMA register offsets
CTRL     = 0x00
STATUS   = 0x04
SRC_ADDR = 0x08
DST_ADDR = 0x0C
LENGTH   = 0x10
INT_EN   = 0x14
INT_STAT = 0x18

# STATUS bit masks
BUSY  = 0x01
DONE  = 0x02
ERROR = 0x04


async def reset_dut(dut, cycles=10):
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, cycles)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def wait_for_done(axil, clk, timeout_cycles=50000):
    """Poll the DMA STATUS register until DONE or ERROR bit is set."""
    for _ in range(timeout_cycles):
        rd = await axil.read(STATUS, 4)
        st = struct.unpack("<I", rd.data)[0]
        if st & DONE:
            return st
        if st & ERROR:
            raise AssertionError(f"DMA reported ERROR: STATUS=0x{st:08X}")
        await RisingEdge(clk)
    raise TimeoutError("DMA did not complete within timeout")


@cocotb.test()
async def test_dma_basic_transfer(dut):
    """DMA copies 4 words from source region to destination region."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    # Control slave: testbench drives DMA configuration registers
    ctrl = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst_n,
                         reset_active_level=False)

    # Memory slave: responds to the DMA's AXI4-Lite master read/write
    mem = AxiLiteRam(AxiLiteBus.from_prefix(dut, "m_axil"), dut.clk, dut.rst_n,
                     reset_active_level=False, size=2**16)

    SRC = 0x0000
    DST = 0x0100
    WORDS = 4
    BYTES = WORDS * 4

    # Pre-fill source region via backdoor
    src_data = [0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xABCDEF01]
    for i, val in enumerate(src_data):
        mem.write(SRC + i * 4, struct.pack("<I", val))

    # Configure DMA
    await ctrl.write(SRC_ADDR, struct.pack("<I", SRC))
    await ctrl.write(DST_ADDR, struct.pack("<I", DST))
    await ctrl.write(LENGTH,   struct.pack("<I", BYTES))
    # Start transfer
    await ctrl.write(CTRL,     struct.pack("<I", 0x1))

    # Wait for completion
    await wait_for_done(ctrl, dut.clk)

    # Verify destination data
    for i, expected in enumerate(src_data):
        raw = mem.read(DST + i * 4, 4)
        got = struct.unpack("<I", raw)[0]
        assert got == expected, \
            f"Word {i}: expected 0x{expected:08X}, got 0x{got:08X}"


@cocotb.test()
async def test_dma_larger_transfer(dut):
    """DMA copies 16 words (64 bytes) and verifies all."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    ctrl = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst_n,
                         reset_active_level=False)
    mem = AxiLiteRam(AxiLiteBus.from_prefix(dut, "m_axil"), dut.clk, dut.rst_n,
                     reset_active_level=False, size=2**16)

    SRC = 0x0200
    DST = 0x0400
    WORDS = 16
    BYTES = WORDS * 4

    src_data = [i * 0x01010101 + 0x01234567 for i in range(WORDS)]
    for i, val in enumerate(src_data):
        mem.write(SRC + i * 4, struct.pack("<I", val & 0xFFFFFFFF))

    await ctrl.write(SRC_ADDR, struct.pack("<I", SRC))
    await ctrl.write(DST_ADDR, struct.pack("<I", DST))
    await ctrl.write(LENGTH,   struct.pack("<I", BYTES))
    await ctrl.write(CTRL,     struct.pack("<I", 0x1))

    await wait_for_done(ctrl, dut.clk)

    for i, expected in enumerate(src_data):
        expected = expected & 0xFFFFFFFF
        raw = mem.read(DST + i * 4, 4)
        got = struct.unpack("<I", raw)[0]
        assert got == expected, \
            f"Word {i}: expected 0x{expected:08X}, got 0x{got:08X}"


@cocotb.test()
async def test_dma_register_readback(dut):
    """Written configuration registers can be read back correctly."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    ctrl = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst_n,
                         reset_active_level=False)
    # Attach memory so the bus doesn't hang if DMA starts
    mem = AxiLiteRam(AxiLiteBus.from_prefix(dut, "m_axil"), dut.clk, dut.rst_n,
                     reset_active_level=False, size=2**16)

    await ctrl.write(SRC_ADDR, struct.pack("<I", 0xAABBCCDD))
    await ctrl.write(DST_ADDR, struct.pack("<I", 0x11223344))
    await ctrl.write(LENGTH,   struct.pack("<I", 0x00000020))
    await ctrl.write(INT_EN,   struct.pack("<I", 0x3))

    rd = await ctrl.read(SRC_ADDR, 4)
    assert struct.unpack("<I", rd.data)[0] == 0xAABBCCDD
    rd = await ctrl.read(DST_ADDR, 4)
    assert struct.unpack("<I", rd.data)[0] == 0x11223344
    rd = await ctrl.read(LENGTH, 4)
    assert struct.unpack("<I", rd.data)[0] == 0x00000020
    rd = await ctrl.read(INT_EN, 4)
    assert (struct.unpack("<I", rd.data)[0] & 0x3) == 0x3


@cocotb.test()
async def test_dma_done_interrupt(dut):
    """IRQ is asserted when done and int_en[0] is set."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    ctrl = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst_n,
                         reset_active_level=False)
    mem = AxiLiteRam(AxiLiteBus.from_prefix(dut, "m_axil"), dut.clk, dut.rst_n,
                     reset_active_level=False, size=2**16)

    mem.write(0x0000, struct.pack("<I", 0x12345678))

    await ctrl.write(SRC_ADDR, struct.pack("<I", 0x0000))
    await ctrl.write(DST_ADDR, struct.pack("<I", 0x0010))
    await ctrl.write(LENGTH,   struct.pack("<I", 4))
    await ctrl.write(INT_EN,   struct.pack("<I", 0x1))   # done_ie
    await ctrl.write(CTRL,     struct.pack("<I", 0x1))

    await wait_for_done(ctrl, dut.clk)
    await ClockCycles(dut.clk, 5)

    assert dut.irq.value == 1, "IRQ should be high after transfer completes with done_ie=1"

    # Clear interrupt status (w1c)
    await ctrl.write(INT_STAT, struct.pack("<I", 0x1))
    await ClockCycles(dut.clk, 2)

    rd = await ctrl.read(INT_STAT, 4)
    assert (struct.unpack("<I", rd.data)[0] & 0x1) == 0, \
        "INT_STAT done bit should be cleared after w1c write"
