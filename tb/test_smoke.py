import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, NextTimeStep


@cocotb.test()
async def accumulator_test(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # reset
    dut.rst_n.value = 0
    dut.en.value = 0
    dut.data_in.value = 0

    await RisingEdge(dut.clk)
    await ReadOnly()
    await RisingEdge(dut.clk)
    await ReadOnly()

    assert int(dut.acc.value) == 0
    assert int(dut.carry.value) == 0

    await NextTimeStep()
    dut.rst_n.value = 1

    model_acc = 0
    model_carry = 0

    for i in range(20):
        # 先准备“下一拍要采样”的输入
        data = random.randint(0, 255)
        dut.en.value = 1
        dut.data_in.value = data

        # 这一拍采样输入并更新寄存器
        await RisingEdge(dut.clk)
        await ReadOnly()

        sum9 = model_acc + data
        expected_acc = sum9 & 0xFF
        expected_carry = 1 if sum9 > 0xFF else 0

        acc_val = int(dut.acc.value)
        carry_val = int(dut.carry.value)

        dut._log.info(
            f"[ADD ] cycle={i:02d} data={data:3d} "
            f"acc={acc_val:3d} carry={carry_val} "
            f"expected_acc={expected_acc:3d} expected_carry={expected_carry}"
        )

        assert acc_val == expected_acc
        assert carry_val == expected_carry

        model_acc = expected_acc
        model_carry = expected_carry

        # 离开 ReadOnly，再改下一拍输入
        await NextTimeStep()
        dut.en.value = 0
        dut.data_in.value = random.randint(0, 255)

        await RisingEdge(dut.clk)
        await ReadOnly()

        assert int(dut.acc.value) == model_acc
        assert int(dut.carry.value) == model_carry

        await NextTimeStep()
