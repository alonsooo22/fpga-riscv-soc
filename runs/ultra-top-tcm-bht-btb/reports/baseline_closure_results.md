# Ultra scalar BHT+BTB 基线闭合结果

日期：2026-09-08。所有“当前”结果均来自本实验目录；旧结果保留为历史引用，不覆盖原报告。

## 1. CoreMark 516 回归

固定软件为 `benchmarks/coremark-ultra/build/xpack15.2-opt3-iter-516/coremark.elf`，编译选项、链接布局、TCM 和 signature 区间不变。停机 PC 为 `_halt=0x202c`。下表的历史值来自上一轮对应配置；当前值来自本轮最终日志或同一 RTL 配置下已保存的最终日志。

| 配置 | 当前日志 | 历史日志属性 | cycles 当前/历史 | retired 当前/历史 | CPI | CM/MHz | scoreboard stall | branch flush | CRC |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| A0 | [a0 final3](baseline_closure_a0_coremark_516_final3.log) | 本轮重新生成 | 200045542 / 200045542 | 150778557 / 150778557 | 1.326750607 | 2.579412642 | 12368613 | 36898412 | e9f5/e714/1fd7/8e3a/e6dc |
| A1 | [a1 final3](baseline_closure_a1_coremark_516_final3.log) | 本轮重新生成 | 170776426 / 170776426 | 150778557 / 150778557 | 1.132630723 | 3.021494313 | 12368613 | 7629296 | e9f5/e714/1fd7/8e3a/e6dc |
| D0 | [d0 final2](baseline_closure_d0_coremark_516_final2.log) | 本轮最终日志复用 | 218494748 / 218494748 | 150778556 / 150778556 | 1.449110230 | 2.361612829 | 12368613 | 36898412 | e9f5/e714/1fd7/8e3a/e6dc |
| D1 | [d1 final](baseline_closure_d1_coremark_516_final.log) | 修改前实验最终日志复用；本轮未重复长测 | 174591074 / 174591074 | 150778556 / 150778556 | 1.157930402 | 2.955477552 | 12368613 | 7629296 | e9f5/e714/1fd7/8e3a/e6dc |

结论：列出的周期、退休指令、CPI、scoreboard stall、flush、CRC 和预测统计均为回归一致，已测程序未出现差异。此结论只针对该 ELF/输入/短测边界，不宣称所有输入的周期级等价。

四组日志都包含 CoreMark 的短测提示 `Must execute for at least 10 secs for a valid result`。因此这里的状态是“短测数据/签名回归 PASS”，不是官方 10 秒有效成绩；正式比赛测量留到后续阶段。

### 1.1 分支和停顿统计

| 配置 | resolved | conditional | JAL | JALR/RET | BTB hit | BTB miss | pred_taken | correct | mispredict | branch request/redirect |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A0 | 30591841 | 27334861 | 2548345 | 708635 | 0 | 29883206 | 0 | 12137700 | 17745506 | 18449206 |
| A1 | 30591829 | 27334849 | 2548345 | 708635 | 27680547 | 2202647 | 16868947 | 26776118 | 3107076 | 3814648 |
| D0 | 30591841 | 27334861 | 2548345 | 708635 | 0 | 29883206 | 0 | 12137700 | 17745506 | 18449206 |
| D1 | 30591829 | 27334849 | 2548345 | 708635 | 27680547 | 2202647 | 16868947 | 26776118 | 3107076 | 3814648 |

`branch_flush` 为 A0/D0 `36898412`、A1/D1 `7629296`；A1/D1 相对关闭预测对照的历史 flush reduction 为 `79.323511267%`。这些是已测 CoreMark 运行的统计，不是对其他程序的保证。

## 2. 资源和历史 LUT 例外

### 2.1 当前 post-route 顶层和层次资源

| 配置/约束 | 顶层 Slice LUT | LUT logic | LUTRAM | 顶层 FF | BRAM36 | DSP | `u_core` LUT（logic/mem） | `u_core` FF | `u_branch_predict` LUT（logic/mem） | predictor FF |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | --- | ---: |
| D0, 100 MHz | 3421 | 3165 | 256 | 1752 | 16 | 4 | 3167 (2911/256) | 1397 | — | — |
| D1, 100 MHz | 3741 | 3372 | 369 | 1877 | 16 | 4 | 3487 (3118/369) | 1524 | 200 (87/113) | 64 |
| D1, 80 MHz | 3537 | 3168 | 369 | 1868 | 16 | 4 | 3283 (2914/369) | 1517 | 200 (87/113) | 64 |

报告路径：

- D0：[utilization.rpt](../../../vivado/ultra_scalar_bht_btb_xc7z020/reports/baseline_closure/param_sweep/D0/utilization.rpt)、[utilization_hierarchical.rpt](../../../vivado/ultra_scalar_bht_btb_xc7z020/reports/baseline_closure/param_sweep/D0/utilization_hierarchical.rpt)
- D1：[utilization.rpt](../../../vivado/ultra_scalar_bht_btb_xc7z020/reports/baseline_closure/param_sweep/D1/utilization.rpt)、[utilization_hierarchical.rpt](../../../vivado/ultra_scalar_bht_btb_xc7z020/reports/baseline_closure/param_sweep/D1/utilization_hierarchical.rpt)
- D1 80 MHz：[utilization.rpt](../../../vivado/ultra_scalar_bht_btb_xc7z020/reports/baseline_closure/dev_frequency_80MHz/D1/utilization.rpt)、[utilization_hierarchical.rpt](../../../vivado/ultra_scalar_bht_btb_xc7z020/reports/baseline_closure/dev_frequency_80MHz/D1/utilization_hierarchical.rpt)

D0 明确包含 256 个 LUTRAM；因此不能笼统写成 predictor-off 顶层 LUTRAM 为 0。`u_branch_predict` 的 200 LUT 是层次分项，不替代顶层总量。

相对历史严格目标的增量保持原结论：A1-A0 为 `+419 LUT/+137 FF`，D1-D0 为 `+320 LUT/+125 FF`。旧 `ΔLUT<=200` 未满足，继续标记 **FAIL/例外建议**；本轮没有把它改写为 PASS，也没有为满足该旧目标重构架构。

## 3. Vivado timing/clock/DRC

Vivado 2022.2 build 3671981，器件 7z020-clg400-1。数值来自最终 `report_timing_summary -delay_type min_max`，不是单条 data path delay 倒数。

| 配置 | 时钟约束 | WNS(ns) | TNS(ns) | TNS failing/total | WHS(ns) | THS(ns) | setup 状态 | 证据目录 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| D0 | 10.000 ns / 100 MHz | -2.566 | -821.001 | 678/5318 | +0.088 | 0 | FAIL | `reports/baseline_closure/param_sweep/D0` |
| D1 | 10.000 ns / 100 MHz | -1.815 | -519.395 | 558/6345 | +0.066 | 0 | FAIL | `reports/baseline_closure/param_sweep/D1` |
| D1 | 12.500 ns / 80 MHz | +0.089 | 0.000 | 0/6329 | +0.099 | 0 | PASS | `reports/baseline_closure/dev_frequency_80MHz/D1` |

D0/D1 的 100 MHz 报告保留真实负 WNS/TNS；D1 80 MHz 报告显示 `All user specified timing constraints are met`。所有三个实现的内部 `unconstrained_internal_endpoints=0`、`no_clock=0`、`multiple_clock=0`、`loops=0`。OOC 接口仍有 138 个 input ports 无 input delay、145 个 output ports 无 output delay，这是适用范围限制，不可省略。

最终 D0/D1/D1-80MHz 均为 DRC 38 warnings、0 errors。警告包括现有 RAMB36 异步控制检查等，不把 warnings 解释为时序通过。

D1 的开发频率采用 80 MHz。按 D1 短测 `2.955477552 CM/MHz` 计算的估算值为 `236.438204160 CM/s`；按 D1 80 MHz 顶层 3537 LUT 计算的估算性能密度为 `0.066847103 CM/s/LUT`。两者都是约束和短测基础上的估算，不是板级测量，也不是精确最高频率。

## 4. 保留的历史证据和失败尝试

原有报告 `reports/branch_predictor_verification.md`、`reports/branch_predictor_coremark_ppa.md`、`reports/rtl_changes.diff` 及原始 Vivado 结果没有被覆盖。Vivado 本轮早期因工具命令兼容性退出的日志也保留在 `reports/baseline_closure/.../vivado_console_invalid_command.log` 和 `vivado_console_invalid_unconstrained.log`；最终结果只引用后续成功完成 route 的报告。

本轮没有将旧失败结果重新包装为通过，也没有用替换软件、改变迭代数、改变计时边界或改变容量来制造一致性。

## 5. 总结

- 功能：单元、真实 IRQ、错误路径副作用和前端三场景在测试范围内 PASS。
- 回归：A0/A1/D0/D1 的固定 516 次短测数据和签名一致。
- FPGA：D0/D1 100 MHz setup FAIL；D1 80 MHz 在注明 OOC 约束下 PASS。
- 基线建议：D1 可作为本地 FPGA 后续开发候选，交由独立验收；不能宣称整个 SoC 或正式比赛交付已经闭合。
