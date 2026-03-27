import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


@cocotb.test()
async def toggle_test(dut):
    """
    测试目标：
    1. 复位后 done = 0
    2. 释放复位后，每个周期 done 都翻转
    """

    cocotb.log.info("==== 测试开始 ====")

    # 1️⃣ 启动时钟（10ns周期）
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # 2️⃣ 进入复位
    dut.rst_n.value = 0

    # 等两个周期（保证复位生效）
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # 检查复位值
    assert int(dut.done.value) == 0, "复位后 done 应该为 0"

    cocotb.log.info("复位检查通过")

    # 3️⃣ 释放复位
    dut.rst_n.value = 1

    await RisingEdge(dut.clk)

    # 4️⃣ 开始检测翻转
    prev = int(dut.done.value)

    for i in range(5):
        await RisingEdge(dut.clk)

        curr = int(dut.done.value)

        cocotb.log.info(f"cycle {i}: prev={prev}, curr={curr}")

        # 核心检查：必须翻转
        assert curr == (1 - prev), f"done 没有翻转！cycle={i}"

        prev = curr

    cocotb.log.info("==== 测试通过 ====")
