# Ultra scalar BHT+BTB microarchitecture

Status: approved implementation contract for the isolated `ultra-top-tcm-bht-btb` experiment.

This note binds the cycle-level implementation. The supplied implementation plan and the existing Ultra scalar interfaces are authoritative; this document does not add a new prediction algorithm, pipeline stage, cache, or execution resource.

## Scope and parameters

The experiment adds a fixed-capacity predictor. Only the feature enable is a
public parameter:

```verilog
SUPPORT_BRANCH_PREDICTION = 0
```

When enabled, the predictor has exactly 64 direct-mapped entries. The
implementation-local constants are `BTB_ENTRIES=64`, `INDEX_W=6`, and
`TAG_W=24`; lookup and update use `PC[7:2]` as the index and `PC[31:8]` as
the complete tag. Capacity is not passed through `riscv_core`,
`riscv_tcm_top`, build commands, or Vivado generics.

Each entry contains:

| Field | Width | Reset/update behavior |
| --- | ---: | --- |
| `btb_valid` | 1 | Reset and `FENCE.I` clear valid bits only |
| `btb_tag` | `32-(INDEX_W+2)` | Synchronous update, resetless distributed RAM |
| `btb_target` | 32 | Synchronous update, resetless distributed RAM |
| `btb_is_jal` | 1 | Synchronous update, resetless distributed RAM |
| `bht_counter` | 2 | Synchronous update, resetless distributed RAM; first allocation initializes from the resolved outcome |

For the XC7Z020 default (`INDEX_W=6`), the four resetless data fields are
implemented as explicit `RAM64X1D` primitives.  Their `A/SPO` port is the
synchronous-write/update-address side and their `DPRA/DPO` port is the
independent asynchronous lookup side.  The valid vector remains resettable
FF state.  This preserves the two independent reads needed for lookup and
update-hit detection while making the intended LUTRAM mapping explicit.

Only conditional branches (`BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`) and `JAL` are trained and predicted. `JALR`, `RET`, indirect calls, CSR redirects, traps, `xRET`, and interrupts retain the original execution-level redirect path.

## Module hierarchy and ports

`riscv_core` owns the predictor instance so that the predictor update can use the resolved execution result while the fetch unit owns the lookup PC and request metadata.

### `riscv_branch_predict`

| Port | Direction | Meaning |
| --- | --- | --- |
| `clk_i`, `rst_i` | input | Existing scalar clock and active-high asynchronous reset |
| `invalidate_i` | input | `FENCE.I` invalidation; has priority over an update |
| `lookup_pc_i` | input | Registered `riscv_fetch.pc_f_q` |
| `lookup_hit_o` | output | Valid + complete-tag hit, used only for statistics/assertions |
| `lookup_taken_o` | output | Safe predicted direction; zero on miss or when disabled |
| `lookup_target_o` | output | Table target; zero on miss or when disabled |
| `update_valid_i` | input | One valid, resolved conditional/JAL update |
| `update_pc_i` | input | Resolved branch PC |
| `update_target_i` | input | Execution-computed PC-relative target |
| `update_is_jal_i` | input | One for `JAL`, zero for a conditional branch |
| `update_taken_i` | input | Resolved direction |
| `update_hit_o` | output | Whether the resolved PC occupied the table before this update |

The table uses asynchronous combinational reads and synchronous writes. There is no update-to-lookup bypass. The disabled generate branch drives safe zeros and contains no predictor table state, allowing synthesis to remove the predictor completely.

### Fetch/decode metadata ports

`riscv_fetch` receives `prediction_taken_i` and `prediction_target_i`, and exposes `prediction_pc_o = pc_f_q` to the core predictor. On `icache_rd_o && icache_accept_i`, it updates `pc_d_q` and `pred_taken_q` together. The next request PC is selected as follows:

```text
redirect request accepted -> existing redirect PC
otherwise if predictor taken -> predictor target
otherwise -> current fetch PC + 4
```

The response skid buffer expands by one bit and stores `{fault_page, fault_fetch, pred_taken, pc, instruction}`. `fetch_pred_taken_o` is sourced from the same skid/direct-response choice as the PC and instruction.

`riscv_decode` carries the bit through the existing optional extra decode register. With `EXTRA_DECODE_STAGE=1`, valid, faults, instruction, PC, and prediction are captured in one register transaction. With `EXTRA_DECODE_STAGE=0`, the prediction bit is straight-through.

`riscv_issue` carries the bit to `opcode_pred_taken_o` beside the existing opcode and PC. The execution unit consumes it only when `opcode_valid_i` is asserted.

## Execution and redirect contract

The existing `branch_d_exec_request` meaning is split without changing actual branch semantics:

| Signal | Meaning and consumer |
| --- | --- |
| `branch_d_exec_taken` | Actual resolved taken direction for `riscv_pipe_ctrl`; it continues to drive branch-target metadata and target-misalignment detection |
| `branch_d_exec_target` | Execution-computed target used by `riscv_pipe_ctrl` |
| `branch_d_exec_mispredict` | Only the front-end redirect/squash request |
| `branch_d_exec_correction_pc` | Correct next PC for a misprediction |

The correction rules are:

| Prediction | Actual | Correction PC |
| --- | --- | --- |
| not taken | taken conditional/JAL | actual execution target |
| taken | not taken conditional | branch PC + 4 |
| taken | taken conditional/JAL | no redirect |
| no prediction | taken `JALR`/`RET` | existing execution target |

`riscv_issue.branch_request_o` is `branch_csr_request_i | branch_d_exec_mispredict_i`. CSR/trap redirects retain priority for `branch_pc_o` and `branch_priv_o`. A correctly predicted direct branch is silent: it does not generate a front-end redirect or decode squash.

The predictor update record is generated only from a valid issued execution instruction. It contains the resolved PC, target, direction, prediction bit, and whether the instruction was a direct `JAL`. `JALR`/`RET` are explicitly excluded. Interrupt launch, invalid/faulted instructions, killed instructions, and taken misaligned direct targets do not train the table.

## Timing, stall, redirect, and response behavior

1. Lookup is driven by the already registered fetch PC; instruction data is never decoded to form a prediction.
2. A prediction is associated with the memory request, not with the cycle in which the memory response happens to arrive.
3. `pc_d_q`, `pred_taken_q`, and the response instruction are held through the existing outstanding-request and backpressure behavior.
4. A response entering the skid buffer stores prediction metadata atomically with its PC, instruction, and faults.
5. A redirect request flushes decode through the existing `squash_decode_o` path and suppresses stale instruction responses through the existing response-drop path.
6. A predictor lookup does not bypass or alter `fetch_accept_i`, `icache_accept_i`, `icache_valid_i`, `stall_w`, or TCM request ownership.
7. If redirect and CSR/trap correction are simultaneous, CSR/trap remains the selected front-end redirect.
8. A stalled fetch does not consume or re-train prediction metadata; a resolved instruction updates the predictor once through its registered update record.

## Reset and `FENCE.I`

Reset clears control/valid state in the predictor and fetch metadata. Predictor tag, target, and BHT arrays are not reset, preserving distributed-RAM inference. Invalid entries cannot produce a prediction because valid and full-tag match are required. `FENCE.I` clears all BTB valid bits with update priority below invalidation; BHT data is left untouched and cannot be observed until a subsequent valid allocation.

## Predictor-off behavior

The default generate branch drives `lookup_taken_o=0`, `lookup_target_o=0`, and `lookup_hit_o=0`. Fetch therefore follows the original sequential `PC+4` path. Execution treats every direct taken conditional/JAL as a misprediction, which reproduces the current taken-branch redirect behavior; not-taken conditionals remain silent. `JALR`/`RET` remain unconditional execution redirects. No predictor arrays are elaborated in this branch.

## Checkpoints and assertions

The unit test and integration checks are recorded in
`reports/branch_predictor_verification.md`.  The executed checks cover:

- reset/FENCE.I miss behavior and disabled safe outputs;
- complete-tag protection and direct-mapped replacement;
- all four saturating-counter states and saturation boundaries;
- first allocation for taken/not-taken conditional branches and `JAL`;
- simultaneous lookup/update without a combinational bypass;
- first not-taken allocation in addition to first taken allocation;
- `EXTRA_DECODE_STAGE=0/1` CoreMark alignment;
- actual-taken versus mispredict signal separation through the CoreMark
  counter invariants;
- direct JAL/JALR/RET, FENCE.I, illegal-instruction, and software-interrupt
  integration paths through the isolated directed image.

The unit test directly checks the table properties that can be observed at
the module boundary: a hit requires the valid bit and complete tag, BHT
training saturates at `00`/`11`, invalidation removes predictions, and an
update is not combinationally bypassed into lookup.  The integration report
separately marks checks that require an assertion or formal waveform and were
not available in this scalar testbench.
