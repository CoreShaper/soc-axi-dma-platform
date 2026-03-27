import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


@cocotb.test()
async def toggle_test(dut):
    """
    测试目标：
    1. 复位期间 done 应为 0
    2. 释放复位后 done 每个周期翻转一次
    """

    dut._log.info("==== 测试开始 ====")

    # 启动 10ns 时钟
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # 施加复位
    dut.rst_n.value = 0

    # 等待两个时钟，保证复位生效
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # 检查复位值
    assert int(dut.done.value) == 0, "复位后 done 应该为 0"
    dut._log.info("复位检查通过")

    # 释放复位
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    # 检查释放复位后的首拍
    prev = int(dut.done.value)
    assert prev == 1, "释放复位后首拍 done 应该为 1"
    dut._log.info(f"释放复位后首拍：done={prev}")

    # 连续检查翻转行为
    for i in range(5):
        await RisingEdge(dut.clk)
        curr = int(dut.done.value)

        dut._log.info(f"cycle {i}: prev={prev}, curr={curr}")
        assert curr == (1 - prev), f"done 没有翻转！cycle={i}"

        prev = curr

    dut._log.info("==== 测试通过 ====")
