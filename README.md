# soc-axi-dma-platform

A reusable SoC platform with AXI4-Lite interconnect and custom DMA engine,
featuring cocotb-based verification, regression flow, and basic STA closure.

---

## Architecture

```
                  ┌─────────────────────────────────────────┐
                  │              soc_top                     │
                  │                                          │
  uart_rx ───────►│  ┌──────────┐   AXI4-Lite 2M/3S         │
  uart_tx ◄───────│  │ cpu_core │──M0──┐                     │
  uart_irq ◄──────│  └──────────┘      │                     │
  dma_irq ◄───────│                    ▼                     │
  cpu_done ◄──────│  ┌─────────────────────────────────────┐ │
  cpu_error ◄─────│  │       axi_interconnect              │ │
                  │  │  (round-robin arbiter, 2M/3S)       │ │
                  │  └──┬──────────┬──────────┬────────────┘ │
                  │     │S0        │S1         │S2            │
                  │     ▼          ▼           ▼             │
                  │  ┌───────┐ ┌──────┐ ┌─────────────────┐ │
                  │  │axi_ram│ │axi_  │ │   dma_engine    │ │
                  │  │ 16KB  │ │uart  │ │  ctrl (slave)   │ │
                  │  └───────┘ └──────┘ │  data (M1)──────┼─►M1
                  │                     └─────────────────┘ │
                  └─────────────────────────────────────────┘
```

### Address Map

| Peripheral  | Base Address | Size  |
|-------------|-------------|-------|
| RAM         | 0x0000_0000 | 16 KB |
| UART        | 0x1000_0000 | 256 B |
| DMA control | 0x2000_0000 | 256 B |

---

## Components

### `rtl/cpu/cpu_core.v`
Minimal AXI4-Lite master CPU.  Executes a hardcoded instruction ROM with
five opcodes: `NOP`, `WRITE32`, `READ_CHK`, `WAIT_BIT`, `DONE`.

### `rtl/axi/axi_interconnect.v`
2-master / 3-slave AXI4-Lite crossbar with round-robin write and read
arbitration.  Address decode is parameterised by base/mask pairs.

### `rtl/ram/axi_ram.v`
Single-port AXI4-Lite SRAM (default 16 KB, parameterisable depth).
Supports byte-enable strobes.

### `rtl/uart/axi_uart.v`
AXI4-Lite UART with:
- TX and RX 16-entry FIFOs
- Hardware loopback mode
- Programmable baud-rate divisor
- Maskable TX-empty / RX-not-empty interrupts

### `rtl/dma/dma_engine.v`
Custom DMA controller:
- **AXI4-Lite slave** – seven 32-bit control/status registers
  (CTRL, STATUS, SRC_ADDR, DST_ADDR, LENGTH, INT_EN, INT_STAT)
- **AXI4-Lite master** – word-by-word memory-to-memory transfer engine
- Done and error interrupts (write-1-to-clear status)

### `rtl/soc_top.v`
Top-level integration connecting all five components.

---

## Verification

Tests are written with [cocotb](https://www.cocotb.org/) and
[cocotbext-axi](https://github.com/alexforencich/cocotbext-axi).

### Prerequisites

```bash
pip install -r requirements.txt
sudo apt-get install iverilog   # Icarus Verilog simulator
```

### Running individual test suites

```bash
# AXI RAM tests
make -C tb/axi_ram

# UART tests
make -C tb/uart

# DMA engine tests
make -C tb/dma

# SoC integration tests
make -C tb/soc_top
```

To capture waveforms (Icarus Verilog → FST):

```bash
make -C tb/dma WAVES=1
```

### Full regression

```bash
./scripts/run_regression.sh
# or with a different simulator:
./scripts/run_regression.sh --sim icarus
```

---

## Timing constraints

`constraints/soc_top.sdc` provides a basic SDC file targeting **100 MHz**
(10 ns period) for use with any standard place-and-route tool.

---

## Directory structure

```
soc-axi-dma-platform/
├── rtl/
│   ├── axi/          axi_interconnect.v
│   ├── ram/          axi_ram.v
│   ├── uart/         axi_uart.v
│   ├── dma/          dma_engine.v
│   ├── cpu/          cpu_core.v
│   └── soc_top.v
├── tb/
│   ├── axi_ram/      test_axi_ram.py  Makefile
│   ├── uart/         test_uart.py     Makefile
│   ├── dma/          test_dma.py      Makefile
│   └── soc_top/      test_soc_top.py  Makefile
├── scripts/
│   └── run_regression.sh
├── constraints/
│   └── soc_top.sdc
├── requirements.txt
└── README.md
```
