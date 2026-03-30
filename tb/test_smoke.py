import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
import random


@cocotb.test()
async def accumulator_test(dut):
    """
    测试累加器模块：
    1. 复位后 acc 和 carry 应为 0
    2. 使能时，acc 累加 data_in，carry 为进位（溢出）
    """
    dut._log.info("==== 累加器测试开始 ====")

    # 启动时钟，周期 10ns
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # 复位
    dut.rst_n.value = 0
    dut.en.value = 0
    dut.data_in.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # 检查复位值
    assert int(dut.acc.value) == 0, "复位后 acc 应该为 0"
    assert int(dut.carry.value) == 0, "复位后 carry 应该为 0"
    dut._log.info("复位检查通过")

    # 释放复位
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # 测试随机累加
    total = 0
    for i in range(20):
        # 随机产生 0~255 之间的数作为输入
        data = random.randint(0, 255)
        dut.data_in.value = data
        dut.en.value = 1

        await RisingEdge(dut.clk)
	await ReadOnly()
        

        # 累加预期值（9位，包含进位）
        total += data
        expected_acc = total & 0xFF
        expected_carry = (total >> 8) & 1

        acc_val = int(dut.acc.value)
        carry_val = int(dut.carry.value)

        dut._log.info(f"cycle {i}: data_in={data}, acc={acc_val}, carry={carry_val}, total={total}")

        assert acc_val == expected_acc, f"acc 错误: 期望 {expected_acc}, 实际 {acc_val}"
        assert carry_val == expected_carry, f"carry 错误: 期望 {expected_carry}, 实际 {carry_val}"

        # 短暂关闭使能，模拟流水线停顿
        dut.en.value = 0
        await RisingEdge(dut.clk)
	await ReadOnly()
        

        # 关闭使能时值应保持不变
        assert int(dut.acc.value) == acc_val, "使能关闭后 acc 不应变化"
        assert int(dut.carry.value) == carry_val, "使能关闭后 carry 不应变化"

    dut._log.info("==== 测试通过 ====")
