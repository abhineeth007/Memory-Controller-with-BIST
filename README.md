# Dual-Port Memory Controller with BIST

## Overview  
This project implements a synthesizable Verilog RTL controller for a synchronous dual-port memory. It supports concurrent access from two ports and includes conflict handling, banked addressing, and a March C- BIST engine.

## Features  

- Parameterizable data width, address width, and number of banks  
- Synchronous dual-port access  
- Independent address/control for both ports  
- Shared bidirectional data bus with read enable control  
- Bank interleaving using lower address bits  
- Same-address write collision detection  
- Port A priority on write conflicts  
- Busy signals for blocked or BIST-controlled accesses  
- Same-cycle write-to-read forwarding  
- March C- BIST (`bist_active`, `test_done`, `test_fail`)  
- Self-checking testbench  

## Parameters  

- `DATA_WIDTH` (default: 32)  
- `ADDR_WIDTH` (default: 8, depth = 2^ADDR_WIDTH)  
- `NUM_BANKS` (default: 4, power of two)  

## Interface  

### Clock and Reset  
- `clk` – system clock  
- `rst_n` – active-low reset  

### Port A / Port B (same signals for both)  
- `*_en` – enable  
- `*_we` – write enable  
- `*_addr` – address  
- `*_data` – bidirectional data bus  
- `*_drive_en` – read data drive control  
- `*_busy` – indicates blocked access  

### Status / BIST  
- `same_bank_hit` – both ports target same bank  
- `write_collision` – both ports write same address  
- `bist_start` – start test  
- `bist_active`, `test_done`, `test_fail` – BIST status  
- `bist_phase`, `bist_addr` – BIST state  

## Behavior  

**Normal operation**  
- Both ports can access memory in the same cycle  
- Writes occur on the clock edge  
- Reads return data in the next cycle  

**Banking**  
- Lower address bits select the bank  
- Sequential accesses are interleaved  
- `same_bank_hit` indicates contention  

**Collisions**  
- Different addresses → both writes succeed  
- Same address → Port A wins, Port B is blocked  
- Write + read (same address) → read gets forwarded data  

**Data bus**  
- Controller drives bus only during reads  
- Otherwise remains high-impedance  

## BIST (March C-)  

Sequence:  
- Write 0  
- Up: read 0, write 1  
- Up: read 1, write 0  
- Down: read 0, write 1  
- Down: read 1, write 0  
- Final read 0  

Detects common faults such as stuck-at, transition, and address faults.

During BIST:  
- Memory is owned by the BIST logic  
- Both ports are blocked  
- `test_done` indicates completion  
- `test_fail` indicates errors  

## Verification  

Testbench covers:  
- Basic read/write  
- Parallel accesses  
- Bank conflicts  
- Same-address write collisions  
- Forwarding behavior  
- BIST pass/fail cases  

Expected output:
```text
All dual-port memory controller tests passed.
```

## How to Run  

```sh
iverilog -g2012 -o tb/tb_dual_port_mem_controller.out \
    rtl/dual_port_mem_controller.v \
    tb/tb_dual_port_mem_controller.v

vvp tb/tb_dual_port_mem_controller.out
