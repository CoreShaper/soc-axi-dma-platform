"""
AXI-RAM unit test (cocotb)
Exercises write, read-back, and byte-enable functionality.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from cocotbext.axi import AxiLiteBus, AxiLiteMaster
import struct


async def reset_dut(dut, cycles=10):
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, cycles)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def test_single_word_write_read(dut):
    """Write a single word and read it back."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst_n,
                         reset_active_level=False)

    await axil.write(0x00, struct.pack("<I", 0xDEADBEEF))
    data = await axil.read(0x00, 4)
    val = struct.unpack("<I", data.data)[0]
    assert val == 0xDEADBEEF, f"Expected 0xDEADBEEF, got 0x{val:08X}"


@cocotb.test()
async def test_multiple_word_write_read(dut):
    """Write multiple words sequentially and verify all."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst_n,
                         reset_active_level=False)

    test_data = [0xAABBCCDD, 0x11223344, 0x55667788, 0x99AABBCC]
    for i, val in enumerate(test_data):
        await axil.write(i * 4, struct.pack("<I", val))

    for i, expected in enumerate(test_data):
        result = await axil.read(i * 4, 4)
        got = struct.unpack("<I", result.data)[0]
        assert got == expected, f"Addr 0x{i*4:04X}: expected 0x{expected:08X}, got 0x{got:08X}"


@cocotb.test()
async def test_byte_enable(dut):
    """Verify byte-enable (wstrb) masking.

    Prime the word with 0xFFFFFFFF, then write only the low byte (0xAB).
    cocotbext-axi sets WSTRB=0x01 automatically when 1 byte is supplied.
    The three upper bytes must remain 0xFF.
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst_n,
                         reset_active_level=False)

    # Prime with all-1s
    await axil.write(0x10, struct.pack("<I", 0xFFFFFFFF))

    # Write only 1 byte to address 0x10 → WSTRB=0x01 (byte lane 0 only)
    await axil.write(0x10, b"\xAB")

    result = await axil.read(0x10, 4)
    got = struct.unpack("<I", result.data)[0]
    # Byte 0 should be 0xAB, remaining bytes unchanged (0xFF)
    assert (got & 0xFF) == 0xAB, f"Low byte mismatch: 0x{got:08X}"
    assert (got >> 8) == 0xFFFFFF, f"Upper bytes changed: 0x{got:08X}"


@cocotb.test()
async def test_address_boundary(dut):
    """Access the last valid word in the memory."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axil"), dut.clk, dut.rst_n,
                         reset_active_level=False)

    last_word_addr = (4096 - 1) * 4   # 0x3FFC
    await axil.write(last_word_addr, struct.pack("<I", 0xFACEFACE))
    result = await axil.read(last_word_addr, 4)
    got = struct.unpack("<I", result.data)[0]
    assert got == 0xFACEFACE, f"Last word: expected 0xFACEFACE, got 0x{got:08X}"
