import cocotb
from cocotb.triggers import RisingEdge

@cocotb.test()
async def smoke_test(dut):
    dut.rst_n.value = 0
    dut.clk.value = 0

    # reset
    for _ in range(5):
        dut.clk.value = 0
        await RisingEdge(dut.clk)
        dut.clk.value = 1
        await RisingEdge(dut.clk)

    dut.rst_n.value = 1

    # run a few cycles
    for _ in range(5):
        dut.clk.value = 0
        await RisingEdge(dut.clk)
        dut.clk.value = 1
        await RisingEdge(dut.clk)

    assert dut.done.value == 1, "done should be 1"
