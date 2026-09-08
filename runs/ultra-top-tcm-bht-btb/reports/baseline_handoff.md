# Ultra scalar BHT+BTB 基线独立验收交接

交接日期：2026-09-08  
交接对象：架构与工程独立验收任务  
实验目录：`D:/code/FPGA/runs/ultra-top-tcm-bht-btb`  
Vivado 目录：`D:/code/FPGA/vivado/ultra_scalar_bht_btb_xc7z020`

## 1. 一句话状态

这是一个**测试范围内功能已通过、固定 516 次短测回归一致、D1 在 80 MHz OOC 约束下实现通过的开发基线候选**；它还不是完整 SoC/板级/比赛交付，也没有把 100 MHz setup 失败或旧 LUT 目标失败改写掉。

## 2. 验收入口

先读：

1. [docs/baseline_closure_contract.md](../docs/baseline_closure_contract.md)
2. [baseline_closure_verification.md](baseline_closure_verification.md)
3. [baseline_closure_results.md](baseline_closure_results.md)
4. [baseline_closure_changes.diff](baseline_closure_changes.diff)
5. [baseline_closure_prechange.md](baseline_closure_prechange.md)

稳定版本锚点是 verification 报告中的关键源码 SHA-256。当前目录无 VCS 元数据；生成的 `verilator.vcd` 等旧产物可能留有历史层次符号，不是活动源码/构建参数。

关键波形：[top_tcm_axi/tb/verilator.vcd](../top_tcm_axi/tb/verilator.vcd)。它作为可查看的保留产物交接；若验收需要严格绑定当前 hash，应按同一脚本以 `ENABLE_WAVES=yes` 重新生成。

## 3. 功能闭合状态

### 已通过的测试范围

- 预测器真实 64 项单元：容量、PC[7:2] 索引、PC[31:8] tag、冲突替换、index 0/63、BHT 00/11 饱和和替换初始化、reset/FENCE.I/JAL、独立 lookup/update、同周期读写、predictor-off 安全输出。
- A1/D1 真实外部 IRQ；D0 predictor-off 对照：`intr_in` 实际驱动，屏蔽时不进 handler，enable 后进入 machine external interrupt，`mcause=0x8000000b`，实际接受边界 `mepc=0x2050`，源撤销后 `mip=0`，程序经 mret 完成。
- IRQ 期间的目标分支 `0x2054` 有 branch window 和 exact mispredict 命中日志；A1/D1 预测打开和 D0 关闭均有证据。
- A1/D1 错误路径副作用和 D0/A0 对照：错误路径寄存器/TCM/CSR/MMIO 均无副作用；正确路径值和两笔实际 MMIO AXI 写事务均可见。
- 前端三个基础压力场景：stall 保持、skid+redirect 丢弃、redirect 后旧 outstanding response 丢弃；每个场景有 `FRONT_HIT` 日志。

功能结论：**上述已测范围 PASS，无已观测功能错误。** 这不是形式证明，也不是所有输入下周期级等价。

### 功能方面仍需注意

前端 fixture 把 correction redirect 与预测元数据交错，IRQ fixture 把真实 IRQ 与误预测交错；尚未将 stall/skid/late-response 与真实 IRQ 合并成一条统一长场景，也没有逐条 retired-PC 白名单。因此这两项应作为独立验收的加强检查，而不是宣称组合覆盖完成。

## 4. CoreMark 回归状态

四组配置均使用相同的 516 次 CoreMark ELF、编译选项、链接布局、TCM 和 signature 边界：

| 配置 | cycles | retired | CPI | CM/MHz | CRC | 回归 |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| A0 | 200045542 | 150778557 | 1.326750607 | 2.579412642 | e9f5/e714/1fd7/8e3a/e6dc | PASS |
| A1 | 170776426 | 150778557 | 1.132630723 | 3.021494313 | e9f5/e714/1fd7/8e3a/e6dc | PASS |
| D0 | 218494748 | 150778556 | 1.449110230 | 2.361612829 | e9f5/e714/1fd7/8e3a/e6dc | PASS |
| D1 | 174591074 | 150778556 | 1.157930402 | 2.955477552 | e9f5/e714/1fd7/8e3a/e6dc | PASS |

结论是**短测 CRC/计数回归一致**；signature 中的 CoreMark “至少 10 秒”提示仍存在，正式不少于 10 秒成绩未执行，不能称为正式有效 CoreMark 成绩。D1 已保存的最终日志直接复用；用户要求停止重复长测后，没有把保留的中断重跑日志作为证据。

## 5. Vivado 实现/时序状态

| 配置 | 频率约束 | WNS | TNS | hold | 状态 |
| --- | ---: | ---: | ---: | ---: | --- |
| D0 | 100 MHz | -2.566 ns | -821.001 ns | WHS +0.088 ns / THS 0 | setup FAIL |
| D1 | 100 MHz | -1.815 ns | -519.395 ns | WHS +0.066 ns / THS 0 | setup FAIL |
| D1 | 80 MHz | +0.089 ns | 0 ns | WHS +0.099 ns / THS 0 | 约束条件下 PASS |

D1 80 MHz 只可称“该约束条件下通过时序的开发频率”。不是板级实测、不是精确最高频率；不使用单条 Data Path Delay 倒数冒充 Fmax。D0/D1 实现均 DRC 38 warnings/0 errors；OOC 仍有 138 个输入和 145 个输出缺少 I/O delay，详见 check_timing。

## 6. 尚未执行或不应误读的项目

- 正式不少于 10 秒 CoreMark 测量。
- 形式验证、完整 ISA 证明、板级时钟/IO 实测。
- 真实 IRQ 与所有前端 backpressure 场景的统一组合测试、逐条 retired-PC 顺序白名单。
- Cache、NPU、RAS、GShare、双发射、紫光迁移和其他后续功能。
- 100 MHz timing closure：本轮明确保留 setup FAIL，未为时序改变架构。

## 7. 旧 LUT 目标例外

旧 `ΔLUT<=200` 目标未达成：历史/当前对照均为 A1-A0 `+419 LUT`、D1-D0 `+320 LUT`。本轮不把该 FAIL 改写为 PASS，也不把 predictor hierarchy 的约 200 LUT 当成顶层增量；D0 顶层本身包含 256 LUTRAM。该项应作为基线评审的明确例外。

## 8. 验收建议

建议验收任务按“功能闭合、短测回归、Vivado 实现”三条独立结论记录，并把上述组合压力、正式 10 秒 CoreMark、形式/板级验证列为后续闭合项。若接受当前范围，D1 可作为本地 XC7Z020 后续开发基线；若验收要求包含完整组合压力、正式 CoreMark 或 100 MHz setup，则状态应保持“待闭合候选”，而不是 PASS。
