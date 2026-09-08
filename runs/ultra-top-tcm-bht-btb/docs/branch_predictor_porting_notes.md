# Branch predictor porting notes

This experiment is an isolated port into `D:/code/FPGA/runs/ultra-top-tcm-bht-btb`. The reference directories under `D:/code/FPGA/references` are read-only and were not modified.

## Source traceability

| Implemented behavior | Reference | Reference location | Ultra adaptation |
| --- | --- | --- | --- |
| Direct-mapped BHT/BTB table split by one index | kas030 `mycpu_if_stage.sv` | `module branch_predictor`, lines 356-390 | Rewritten in Verilog-2001 style as `riscv_branch_predict.v`; capacity is fixed at 64 entries with index `PC[7:2]` and complete tag `PC[31:8]`. |
| Valid, target, JAL type, and BHT state | kas030 `mycpu_if_stage.sv` | lines 373-380 and 397-421 | Kept as separate table fields. Valid bits are the only table state cleared by reset/`FENCE.I`; target/tag/JAL/BHT are resetless `RAM64X1D` data bits so Vivado maps them to LUTRAM. On a direct-mapped tag replacement, the BHT is initialized from the new outcome so an old tag's history is not reused. |
| 2-bit saturating update | kas030 `mycpu_if_stage.sv` | lines 402-421 | Preserved increment/decrement and `00`/`11` saturation, with the same first-allocation states: taken conditional `10`, not-taken conditional `00`, JAL `01`. |
| Asynchronous predictor target selection | kas030 `mycpu_if_stage.sv` | lines 294-319 and 383-389 | Reduced from the dual-fetch next-PC network to one scalar fetch PC. The target is used only in `riscv_fetch`'s next-PC mux. |
| Directional misprediction comparison | kas030 `mycpu_redirect_ctrl.sv` | lines 27-48 | Applied to Ultra's existing execute signals: conditional branches compare prediction versus actual direction; JAL only misses when not predicted; JALR/RET always use the existing execution redirect. No 32-bit predicted-target comparison is added for direct branches/JAL. |
| Correct predictions are silent | Ultra biRISC-V `biriscv_npc.v` | lines 251-255 and 375-380 | `riscv_issue.branch_request_o` now combines CSR redirect with the new mispredict signal. A correct direct prediction does not enter the fetch redirect path. |
| Request/response prediction metadata alignment | Ultra biRISC-V `biriscv_fetch.v` | lines 274-302 | Scalar `riscv_fetch` stores one `pred_taken` bit beside `pc_d_q` and adds it to the skid buffer. No dual-word metadata or second issue slot is imported. |
| Extra decode-stage metadata | Ultra biRISC-V `biriscv_decode.v` | lines 101-116 and 168-188 | The Ultra optional decode register carries one extra prediction bit with the existing valid/fault/instruction/PC payload; the straight-through configuration remains straight-through. |

## Ultra-specific mechanical changes

1. Added `SUPPORT_BRANCH_PREDICTION` to `riscv_core` and `riscv_tcm_top`; the predictor capacity is an internal 64-entry invariant and is not a public parameter.
2. Added `riscv_branch_predict.v` to the scalar core source set.
3. Split the old execution signal into actual-taken, actual-target, mispredict, and correction-PC responsibilities. `riscv_pipe_ctrl` still receives actual taken and actual target, so target-misalignment and NPC metadata keep their old meaning.
4. Added the accepted-request prediction bit to fetch, decode, issue, and execute. The 32-bit predicted target does not cross the scalar pipeline.
5. Added a registered direct-branch/JAL update record in `riscv_exec`; it excludes JALR/RET, interrupts, invalid instructions, and taken misaligned targets.
6. Added simulation-only performance observations under the existing `ULTRA_PERF_COUNTERS` guard. These are not present in the Vivado synthesis configuration.
7. Adapted the existing Vivado scripts to the isolated run root and added predictor-off/on parameter sweeps without changing TCM, LSU, forwarding, scoreboard policy, or pipeline stages.

The first array-description attempt produced FF storage in the A1/D1
post-route hierarchy.  The algorithm and table shape were held constant; the
storage description was then changed to the Xilinx `RAM64X1D` primitive with
a small Verilator model.  The final hierarchy reports show 113 LUTRAM in the
predictor and no predictor BRAM/DSP usage.

## Deliberately not ported

The biRISC-V full-associative BTB search, dual-fetch/dual-issue machinery, GShare history, RAS, speculative global history, second execution slot, and cache logic are not present. The Ibex static predictor is not used. The kas030 CRC/benchmark-specific logic is not used.

## Porting review

The only behavior-changing path is the approved prediction next-PC selection and its corresponding mispredict correction. Predictor-off is the compatibility mode and is checked against the isolated baseline CoreMark/ISA run before predictor-on measurements are accepted.
