# v0.1.0-coremark-baseline

状态：**ACCEPTED — CoreMark 开发版本基线**。

决定日期：2026-09-08。用户明确将当前验收范围收敛为“核心能跑 CoreMark”，其余小测试暂缓。本决定替代上一轮“必须补齐三项测试证据才能闭合本版”的门槛；不更改旧报告的历史结论，也不把未执行项目写成通过。

## 当前基线

- 主配置 D1：extra decode=1，Xilinx RF=1，预测器=1。
- 64-entry direct-mapped BTB + 2-bit BHT，完整 PC tag。
- 条件分支和 JAL 预测；保留原有其他重定向路径。
- `top_tcm_axi`、64 KiB TCM；本地 XC7Z020 / Vivado 2022.2。
- 固定516次 CoreMark，xPack GCC15.2、-O3，已有 CRC 和计数结果可复用。

| 配置 | cycles | retired | CoreMark/MHz |
|---|---:|---:|---:|
| A0 | 200045542 | 150778557 | 2.579412642 |
| A1 | 170776426 | 150778557 | 3.021494313 |
| D0 | 218494748 | 150778556 | 2.361612829 |
| D1 | 174591074 | 150778556 | 2.955477552 |

D1 80 MHz OOC：WNS +0.089 ns、TNS 0、WHS +0.099 ns；3537 LUT、1868 FF、16 BRAM36、4 DSP。内部约束通过，I/O delay 尚不完整；100 MHz setup 仍未通过。短测不作为正式不少于10秒比赛成绩。

## 用户接受的延期项

1. IRQ 与误预测的精确窗口覆盖和恢复检查。
2. 错误路径副作用用例的逐目标预测/在途命中证明。
3. 前端请求/响应记账与 exactly-once 检查。
4. 真实代码 diff 交付规范（旧 .diff 实为说明清单）；从本版本开始使用 Git。
5. 正式10秒测量、完整异常/中断符合性、形式/板级验证及完整 SoC 集成。

旧 ΔLUT≤200 未满足，作为当前版本接受的资源例外，不启动压面积返工。后续先完成基础 CPU/SoC 和高阶设计，再考虑应用；紫光迁移留到相应阶段。

## 证据与版本策略

完整结果入口：`runs/ultra-top-tcm-bht-btb/reports/baseline_closure_results.md`。旧验收意见保留在 `reports/baseline_acceptance_2026-09-08.md`。

本次建库不修改 RTL、不运行 CoreMark 或 Vivado。保留必要的既有日志、signature、正式选用的 benchmark ELF 与实现报告；旧中间构建和大型波形留在本地、不入 Git。

后续根据行为/配置/软件/约束变化选择验证。文档或独立测试监视器变化不使已有性能数据自动失效，不要求全工作区快照一致后重跑全部实验。
