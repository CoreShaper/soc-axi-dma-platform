"""
SoC Top integration test (cocotb)

The soc_top instantiates cpu_core, axi_interconnect, axi_ram, axi_uart, and
dma_engine.  The CPU runs a hardcoded program that:
  1. Writes two words to RAM
  2. Reads them back and compares
  3. Writes to the UART TX register
  4. Configures and starts the DMA
  5. Waits for DMA done
  6. Reads back the DMA destination and checks the copy was correct
  7. Asserts cpu_done

This test simply drives clock/reset and waits for cpu_done to be asserted
without cpu_error.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, with_timeout
from cocotb.utils import get_sim_time


async def reset_dut(dut, cycles=20):
    dut.rst_n.value = 0
    dut.uart_rx.value = 1   # idle line
    await ClockCycles(dut.clk, cycles)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


@cocotb.test(timeout_time=200_000, timeout_unit="ns")
async def test_cpu_program_completes(dut):
    """CPU program should complete without error within the timeout."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    # Wait for cpu_done to be asserted
    while dut.cpu_done.value == 0:
        await RisingEdge(dut.clk)

    elapsed = get_sim_time("ns")
    assert dut.cpu_error.value == 0, \
        f"CPU program reported an error (cpu_error=1) at {elapsed} ns"
    cocotb.log.info(f"CPU program completed successfully at {elapsed} ns")


@cocotb.test(timeout_time=200_000, timeout_unit="ns")
async def test_no_spurious_done_at_reset(dut):
    """cpu_done must not be asserted while reset is active."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    dut.uart_rx.value = 1
    await ClockCycles(dut.clk, 5)
    assert dut.cpu_done.value == 0, "cpu_done should be 0 during reset"
    assert dut.cpu_error.value == 0, "cpu_error should be 0 during reset"
    dut.rst_n.value = 1
