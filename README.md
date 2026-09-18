Phase 1: Blocking Read-Only L1 Data Cache
This repository contains the first milestone toward a non-blocking L1 data
cache. The current design is intentionally simple:
32-bit byte address
32-bit CPU load data
32-byte cache lines
64 direct-mapped sets
2 KiB capacity
read-only CPU interface
one outstanding CPU request
blocking miss handling
simplified whole-line memory refill interface
Repository structure
```text
nonblocking-l1-cache/
|-- README.md
|-- rtl/
|   |-- cache_pkg.sv
|   `-- l1d_cache.sv
|-- tb/
|   |-- simple_memory.sv
|   `-- tb_l1d_cache.sv
`-- sim/
    |-- files.f
    |-- Makefile
    `-- run.do
```
Controller flow
```text
IDLE -> LOOKUP -> RESPONSE -> IDLE                 (hit)

IDLE -> LOOKUP -> REFILL_REQ -> REFILL_WAIT
     -> INSTALL -> LOOKUP -> RESPONSE -> IDLE      (miss)
```
After a refill is installed, the original CPU request is replayed through the
normal lookup path. It should then hit.
Run with Questa/ModelSim
```sh
cd sim
vsim -c -do run.do
```
or:
```sh
cd sim
make questa
```
The testbench checks:
Cold miss and refill for address `0x00001004`.
Same-line hit for address `0x0000100C`.
Direct-mapped conflict miss for address `0x00001804`.
Re-miss for `0x00001004` after the original line was evicted.
Expected final message:
```text
ALL PHASE 1 L1D CACHE TESTS PASSED
```
Current limitations
The design does not yet support stores, dirty lines, two ways, PLRU, AXI,
pipelining, MSHRs or multiple outstanding requests. Those belong to later
milestones and should only be added after this version passes reliably.