# ============================================
# 仿真部分（cocotb + Verilator）
# ============================================
TOPLEVEL_LANG = verilog
SIM = verilator

VERILOG_SOURCES = $(PWD)/rtl/top.v
TOPLEVEL = top
COCOTB_TEST_MODULES = tb.test_smoke

EXTRA_ARGS += --trace --trace-fst --trace-structs

.PHONY: lint
lint:
	verilator --lint-only -Wall $(wildcard rtl/*.v)

.PHONY: sim
sim:
	$(MAKE) -f $(firstword $(MAKEFILE_LIST)) _sim

# 实际仿真规则（避免递归调用）
_sim:
	$(MAKE) -f $(shell cocotb-config --makefiles)/Makefile.sim \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) SIM=$(SIM) \
		VERILOG_SOURCES="$(VERILOG_SOURCES)" \
		TOPLEVEL=$(TOPLEVEL) \
		COCOTB_TEST_MODULES=$(COCOTB_TEST_MODULES) \
		EXTRA_ARGS="$(EXTRA_ARGS)"
	
.PHONY: run
run:
	-$(MAKE) sim
	-mv dump.fst waves/ 2>/dev/null || true
	gtkwave waves/dump.fst

# ============================================
# 综合部分（yosys-sta）
# ============================================
# 综合配置（请根据你的项目修改）
YOSYS_STA_DIR := $(HOME)/tools/yosys-sta   # yosys-sta 的绝对路径
DESIGN := top                              # 顶层模块名，需与 RTL 一致
RTL_FILES := $(wildcard rtl/*.v)           # 所有 RTL 文件
SDC_FILE := constraints/top.sdc            # SDC 文件（可选，但建议提供）
CLK_FREQ_MHZ := 100                        # 目标频率 (MHz)
CLK_PORT_NAME := clk                       # 时钟端口名
SYN_OUT_DIR := ./syn_results               # 综合结果输出目录

.PHONY: syn sta
syn:
	cd $(YOSYS_STA_DIR) && make syn \
		DESIGN=$(DESIGN) \
		RTL_FILES="$(abspath $(RTL_FILES))" \
		SDC_FILE="$(abspath $(SDC_FILE))" \
		CLK_PORT_NAME=$(CLK_PORT_NAME) \
		O="$(abspath $(SYN_OUT_DIR))"

sta:
	cd $(YOSYS_STA_DIR) && make sta \
		DESIGN=$(DESIGN) \
		RTL_FILES="$(abspath $(RTL_FILES))" \
		SDC_FILE="$(abspath $(SDC_FILE))" \
		CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
		CLK_PORT_NAME=$(CLK_PORT_NAME) \
		O="$(abspath $(SYN_OUT_DIR))"

# ============================================
# 清理
# ============================================
.PHONY: clean
clean:
	rm -rf sim_build results.xml  waves/dump.fst
	rm -rf $(SYN_OUT_DIR)
