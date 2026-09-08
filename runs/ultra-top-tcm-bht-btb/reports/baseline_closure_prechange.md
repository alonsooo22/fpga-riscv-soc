# 本轮闭合前快照（不可覆盖的上一轮依据）

快照时间：2026-09-07。本文件记录“闭合 Ultra scalar BHT+BTB 开发基线”开始前的隔离工程状态；上一轮报告和实验产物保持原样，不用本轮结果覆盖。

## 代码/配置快照

上一轮已修改的可读源文件包括：

- `core/riscv/riscv_branch_predict.v`
- `core/riscv/riscv_core.v`
- `core/riscv/riscv_fetch.v`
- `core/riscv/riscv_decode.v`
- `core/riscv/riscv_issue.v`
- `core/riscv/riscv_exec.v`
- `top_tcm_axi/src_v/riscv_tcm_top.v`
- `isa_sim/cosim_api.h`
- `isa_sim/cosim_api.cpp`
- `isa_sim/riscv_main.cpp`
- `top_tcm_axi/tb/testbench.h`
- `sim/branch_predictor/tb_riscv_branch_predict.v`
- `sim/branch_predictor/branch_redirect_test.S/.ld`

上一轮完整的语义变更清单保存在 [rtl_changes.diff](rtl_changes.diff)。本轮只在本文件所对应的状态上追加修改，并以 `baseline_closure_changes.diff` 单独记录。

闭合前的容量配置仍为：

```text
riscv_branch_predict.SUPPORT_BRANCH_PREDICTION = 1 (module default)
riscv_branch_predict.BRANCH_PREDICTOR_INDEX_W  = 6 (module parameter)
riscv_core.BRANCH_PREDICTOR_INDEX_W            = 6 (top-level parameter)
riscv_tcm_top.BRANCH_PREDICTOR_INDEX_W         = 6 (top-level parameter)
```

上一轮单元测试为 `BRANCH_PREDICTOR_INDEX_W=2`，即 4 项测试替代表；本轮将改为真实 64 项实现。上一轮 Vivado A0/A1/D0/D1 sweep 通过脚本 generic 传入容量参数。

## 闭合前 CoreMark 结果

CoreMark ELF 为 `benchmarks/coremark-ultra/build/xpack15.2-opt3-iter-516/coremark.elf`，固定约 516 iterations，`.text=18972` bytes。

| 配置 | Predictor | cycles | retired | CPI | CoreMark/MHz | flush cycles |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A0 | 0 | 200045542 | 150778557 | 1.326750607 | 2.579412642 | 36898412 |
| A1 | 1 | 170776426 | 150778557 | 1.132630723 | 3.021494313 | 7629296 |
| D0 | 0 | 218494748 | 150778556 | 1.449110230 | 2.361612829 | 36898412 |
| D1 | 1 | 174591074 | 150778556 | 1.157930402 | 2.955477552 | 7629296 |

四组 CRC 均为 `e9f5/e714/1fd7/8e3a/e6dc`。详细上一轮软件结果保存在 [branch_predictor_coremark_ppa.md](branch_predictor_coremark_ppa.md)，上一轮验证状态保存在 [branch_predictor_verification.md](branch_predictor_verification.md)。

## 闭合前 Vivado 结果

工具为 Vivado 2022.2 build 3671981，器件 `xc7z020clg400-1`，10 ns 约束。上一轮 post-route 资源/时序如下，作为本轮 D0/D1 重跑和口径修正的对照：

| 配置 | WNS (ns) | TNS (ns) | data path delay (ns) | LUT | LUTRAM | FF | BRAM36 | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A0 | -3.672 | -1918.984 | 13.569 | 3661 | 0 | 2666 | 16 | 4 |
| A1 | -3.518 | -1956.518 | 13.330 | 4080 | 113 | 2803 | 16 | 4 |
| D0 | -2.566 | -821.001 | 12.370 | 3421 | 256 | 1752 | 16 | 4 |
| D1 | -1.815 | -519.395 | 11.685 | 3741 | 369 | 1877 | 16 | 4 |

上一轮的 Fmax 是 `1000/data_path_delay` 的工程估计，不是已验证最高频率；本轮将改用明确的开发频率约束和 setup/hold/clock/unconstrained-path 报告。上一轮 D0/D1 的 `256/369 LUTRAM` 是 Xilinx RF 等既有设计资源，不能归因于 predictor。

## 已知缺口（本轮待闭合）

1. `BRANCH_PREDICTOR_INDEX_W` 是实际只支持 64 项的伪参数。
2. 单元测试没有在 update 时钟沿前有效检查 `update_hit_o`，且失败后 `$finish` 仍可能返回 0。
3. `testbench.h::set_interrupt()` 为空，没有真实外部 `intr_in` 注入验证。
4. 没有独立的 wrong-path register/store/CSR/MMIO 副作用监视器。
5. 没有命中下游 stall、skid + redirect、旧 response drop、交错中断的最小前端压力夹具。
6. 旧报告尚未区分“历史 Fmax 估计”和“本轮约束下通过时序的开发频率”。

本快照只用于追溯。旧报告中的 `CONDITIONAL PASS` 和 LUT 目标例外保持其历史属性，本轮不把它改写为 PASS。
