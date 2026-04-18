# High-Performance Dual-Port Memory Controller with BIST

## Overview

This project implements a synthesizable Verilog RTL memory controller for a synchronous dual-port memory subsystem intended for SoC-style integration. The design goes beyond a simple RAM array by adding collision handling, bank-aware access monitoring, tri-state bus control, and an embedded March C- built-in self-test engine.

The controller supports two independent ports that can issue reads and writes in the same clock cycle. It also exposes status flags that help downstream logic detect contention, stall lower-priority traffic during conflicting writes, and monitor memory self-test completion.

## Features

- Parameterizable data width, address width, and number of banks
- Synchronous dual-port memory access
- Two independent address/control interfaces
- Shared bidirectional data bus per port with explicit read drive-enable signals
- Bank-interleaved addressing using low-order address bits
- Same-address dual-write collision detection
- Port A write priority on simultaneous same-address writes
- Busy signaling for blocked or BIST-owned accesses
- Same-cycle write-to-read data forwarding
- March C- BIST engine with `bist_active`, `test_done`, and `test_fail`
- Self-checking Verilog testbench for corner-case verification

## Directory Structure

```text
dual_port_mem_bist/
|-- rtl/
|   `-- dual_port_mem_controller.v
|-- tb/
|   `-- tb_dual_port_mem_controller.v
`-- README.md
```

## Design Parameters

The top-level module is parameterized as follows:

- `DATA_WIDTH`
  Default: `32`
  Width of each memory word and port data bus.

- `ADDR_WIDTH`
  Default: `8`
  Number of address bits. Total memory depth is `2^ADDR_WIDTH`.

- `NUM_BANKS`
  Default: `4`
  Number of logical memory banks used for interleaved bank selection. This value must be a power of two and cannot exceed the memory depth.

## Top-Level Interface

### Clock and Reset

- `clk`
  System clock. All functional operations and BIST transitions occur on the rising edge.

- `rst_n`
  Active-low reset.

### Port A Interface

- `port_a_en`
  Enables Port A transaction handling.

- `port_a_we`
  Write enable for Port A. `1` selects write, `0` selects read.

- `port_a_addr[ADDR_WIDTH-1:0]`
  Address for Port A access.

- `port_a_data[DATA_WIDTH-1:0]`
  Bidirectional Port A data bus.

- `port_a_drive_en`
  Indicates when the controller is actively driving `port_a_data` during a read.

- `port_a_busy`
  Indicates that Port A is blocked, typically during BIST ownership.

### Port B Interface

- `port_b_en`
  Enables Port B transaction handling.

- `port_b_we`
  Write enable for Port B. `1` selects write, `0` selects read.

- `port_b_addr[ADDR_WIDTH-1:0]`
  Address for Port B access.

- `port_b_data[DATA_WIDTH-1:0]`
  Bidirectional Port B data bus.

- `port_b_drive_en`
  Indicates when the controller is actively driving `port_b_data` during a read.

- `port_b_busy`
  Indicates that Port B is blocked because of BIST or lower-priority write collision handling.

### Status and BIST Interface

- `same_bank_hit`
  Asserts when both ports target the same logical bank in the same cycle.

- `write_collision`
  Asserts when both ports attempt to write the same address in the same cycle.

- `bist_start`
  Starts the BIST engine.

- `bist_active`
  Indicates that the March C- engine currently owns the memory array.

- `test_done`
  Asserts when BIST completes.

- `test_fail`
  Asserts if any March C- readback check fails.

- `bist_phase[2:0]`
  Current BIST FSM phase.

- `bist_addr[ADDR_WIDTH-1:0]`
  Current BIST address pointer.

## Functional Behavior

### Normal Access

- Both ports may access memory in the same cycle.
- Reads are synchronous and data is driven onto the corresponding port bus during the read-valid window.
- Writes update the memory array on the rising clock edge.

### Banking

- Bank selection uses the low-order address bits.
- Sequential addresses are interleaved across banks.
- `same_bank_hit` acts as a contention visibility flag for higher-level arbitration or performance monitoring.

### Collision Handling

- If both ports write different addresses in the same cycle, both writes are accepted.
- If both ports write the same address in the same cycle:
  - Port A wins
  - `write_collision` asserts
  - `port_b_busy` asserts
- If one port writes while the other reads the same address in the same cycle, the read port receives forwarded write data.

### Tri-State Bus Management

- Each port uses an `inout` data bus.
- The controller only drives a bus during a read cycle when the corresponding `*_drive_en` signal is asserted.
- Outside read windows, the controller places the bus in high-impedance state to avoid contention.

## March C- BIST Engine

The built-in self-test engine follows a March C- style sequence:

1. Write `0` to all addresses
2. Sweep upward: read `0`, write `1`
3. Sweep upward: read `1`, write `0`
4. Sweep downward: read `0`, write `1`
5. Sweep downward: read `1`, write `0`
6. Final sweep upward: read `0`

This sequence is intended to detect common memory faults such as:

- Stuck-at faults
- Transition faults
- Address decoder faults
- Some coupling-related faults

During BIST:

- The memory array is owned by the BIST FSM
- `port_a_busy` and `port_b_busy` remain asserted
- External traffic is blocked until the test completes
- `test_done` indicates completion
- `test_fail` indicates at least one readback mismatch

## Verification

The self-checking testbench covers:

- Idle high-impedance bus behavior
- Basic Port A and Port B write/read sequences
- Different-bank simultaneous writes
- Same-bank different-address accesses
- Same-address dual-write collision handling
- Port A priority behavior
- Same-cycle write/read forwarding
- BIST pass behavior on a healthy memory image
- BIST fail behavior using injected memory corruption

Expected simulation result:

```text
All dual-port memory controller tests passed.
```

## How to Run

From `/Users/karanthabhineeth/Documents/New project/dual_port_mem_bist`:

```sh
iverilog -g2012 -o tb/tb_dual_port_mem_controller.out \
    rtl/dual_port_mem_controller.v \
    tb/tb_dual_port_mem_controller.v
vvp tb/tb_dual_port_mem_controller.out
```

## Suggested Resume Description

Designed and verified a parameterizable Verilog dual-port memory controller with synchronous read/write support, same-address collision resolution, bank-aware access handling, tri-state read-bus control, and a March C- BIST engine for production-style memory validation.

## Future Extensions

- Add byte-enable support
- Add ECC or parity generation/checking
- Add registered output timing options
- Add SystemVerilog assertions for protocol checking
- Add a UVM environment for constrained-random verification
- Wrap the controller with FPGA BRAM inference-friendly interfaces
