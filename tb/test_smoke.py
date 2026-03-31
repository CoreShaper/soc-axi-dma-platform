import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, NextTimeStep


@cocotb.test()
async def accumulator_test(dut):
    """
    测试 top 累加器模块：

    1. 复位后 acc=0, carry=0
    2. en=1 时，在时钟上升沿采样 data_in 并执行累加
    3. carry 表示“本拍加法是否产生进位”
    4. en=0 时，acc/carry 保持不变

    时序原则：
    - 写输入：在时钟沿到来之前，或离开 ReadOnly 之后写
    - 读输出：RisingEdge 后再 ReadOnly 中读
    """

    dut._log.info("==== 累加器测试开始 ====")

    # 启动时钟：10ns 周期
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # ----------------------------
    # 初始驱动
    # ----------------------------
    dut.rst_n.value = 0
    dut.en.value = 0
    dut.data_in.value = 0

    # 异步复位拉低后，等两个上升沿观察状态
    await RisingEdge(dut.clk)
    await ReadOnly()
    await RisingEdge(dut.clk)
    await ReadOnly()

    # 复位检查
    acc_val = int(dut.acc.value)
    carry_val = int(dut.carry.value)

    assert acc_val == 0, f"复位后 acc 应为 0，实际为 {acc_val}"
    assert carry_val == 0, f"复位后 carry 应为 0，实际为 {carry_val}"
    dut._log.info("复位检查通过")

    # ----------------------------
    # 释放复位
    # 注意：先离开当前 ReadOnly phase 再写信号
    # ----------------------------
    await NextTimeStep()
    dut.rst_n.value = 1
    dut.en.value = 0
    dut.data_in.value = 0

    # 软件参考模型
    model_acc = 0
    model_carry = 0

    # ----------------------------
    # 随机测试
    # ----------------------------
    for i in range(20):
        # ====== Phase A: 准备本拍输入（给下一个上升沿采样） ======
        data = random.randint(0, 255)
        dut.data_in.value = data
        dut.en.value = 1

        # ====== Phase B: 等待时钟沿，随后读取本拍输出 ======
        await RisingEdge(dut.clk)
        await ReadOnly()

        # 参考模型：本拍执行 model_acc + data
        sum9 = model_acc + data
        expected_acc = sum9 & 0xFF
        expected_carry = 1 if sum9 > 0xFF else 0

        acc_val = int(dut.acc.value)
        carry_val = int(dut.carry.value)

        dut._log.info(
            f"[ADD ] cycle={i:02d} data_in={data:3d} | "
            f"acc={acc_val:3d} carry={carry_val} | "
            f"expected_acc={expected_acc:3d} expected_carry={expected_carry}"
        )

        assert acc_val == expected_acc, (
            f"[ADD ] cycle {i}: acc 错误，期望 {expected_acc}，实际 {acc_val}"
        )
        assert carry_val == expected_carry, (
            f"[ADD ] cycle {i}: carry 错误，期望 {expected_carry}，实际 {carry_val}"
        )

        # 更新模型状态
        model_acc = expected_acc
        model_carry = expected_carry

        # ====== Phase C: 离开 ReadOnly，再改输入，测试 en=0 保持 ======
        await NextTimeStep()

        dut.en.value = 0
        dut.data_in.value = random.randint(0, 255)  # 随便改，en=0 不应影响输出

        # 下一拍：由于 en=0，输出应保持
        await RisingEdge(dut.clk)
        await ReadOnly()

        acc_hold = int(dut.acc.value)
        carry_hold = int(dut.carry.value)

        dut._log.info(
            f"[HOLD] cycle={i:02d} hold_data_in={int(dut.data_in.value):3d} | "
            f"acc={acc_hold:3d} carry={carry_hold} | "
            f"expected_hold_acc={model_acc:3d} expected_hold_carry={model_carry}"
        )

        assert acc_hold == model_acc, (
            f"[HOLD] cycle {i}: en=0 时 acc 不应变化，期望 {model_acc}，实际 {acc_hold}"
        )
        assert carry_hold == model_carry, (
            f"[HOLD] cycle {i}: en=0 时 carry 不应变化，期望 {model_carry}，实际 {carry_hold}"
        )

        # 再离开只读阶段，进入下一轮
        await NextTimeStep()

    dut._log.info("==== 测试通过 ====")
