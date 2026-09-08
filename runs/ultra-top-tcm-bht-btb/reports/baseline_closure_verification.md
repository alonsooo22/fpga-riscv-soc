# Ultra scalar BHT+BTB 基线闭合验证报告

日期：2026-09-08  
目标器件：XC7Z020（7z020-clg400-1）  
工具：Vivado 2022.2 build 3671981；Verilator 5.050；SystemC 2.3.1；riscv-none-elf-gcc 15.2

## 1. 结论摘要

本轮已完成并保留可重跑入口：

- 固定 64 项 BTB/BHT、四组 A0/A1/D0/D1 配置、外部中断真实输入、错误路径副作用监视器和前端握手压力夹具。
- 预测器单元、A1/D1 外部中断、A1/D1 错误路径副作用、三个前端压力场景均有命中日志；D0/A0 提供关闭预测对照，D0 也完成 IRQ/副作用对照。
- 四组 516 次 CoreMark 的 CRC、周期、退休指令、stall/flush 和预测统计与对应历史实验一致；这是短测回归结论，不是 CoreMark 正式不少于 10 秒的有效成绩。
- D0/D1 在 100 MHz OOC 约束下 setup 时序仍不通过；D1 在 80 MHz OOC 约束下 WNS/TNS、hold、clock 和内部 unconstrained 检查通过。

因此，本轮状态为：**测试范围内功能 PASS，短测回归 PASS，D1 80 MHz 开发频率实现 PASS；整体提交独立验收，仍标记为开发基线候选，不宣称完整 SoC、板级实测或比赛交付完成。**

## 2. 保护边界和版本锚点

修改前源码差异、配置和结果已保存于 [baseline_closure_prechange.md](baseline_closure_prechange.md)。原始 `runs/ultra-top-tcm`、原始 Vivado 工程和 `references` 未覆盖；上一轮报告及其旧结果保留。

仿真容器只使用：

```text
D:/code/FPGA/runs/ultra-top-tcm-bht-btb:/work
```

当前源码无 VCS 元数据，因此用关键文件 SHA-256 作为稳定版本锚点：

```text
115F692975169D42A74610C1B6C0726594D7208FCB8BDFFF82C74BC881822505  core/riscv/riscv_branch_predict.v
75B82D5922AB5A70584C2587B0A8F8207260C4EA88CD937C3FA777B40FC5835A  core/riscv/riscv_core.v
58FBD671135809F76DBC154115C0CACAD60F05626E88BE1758E9069E5EFF54ED  top_tcm_axi/src_v/riscv_tcm_top.v
4E584196ADC350EED745EB6CFC3ACD2B373B182FA2460593A4FB07F1D0308C03  top_tcm_axi/tb/testbench.h
6C9C55C0A4EB80C9CD743CD3B3A068D019D7A405760FE740FE1FB22F956D0457  isa_sim/riscv_main.cpp
BC371D2CBF9873DC767469DE932DD249A723F26CC00347476393A0B78ECAAF14  sim/branch_predictor/tb_riscv_branch_predict.v
5E36679983DE20A9EFCCFDB4EDDB242855C84249EB7D7C897921881DEE9A1E61  sim/baseline_closure/tb_frontend_pressure.v
C16AE61C6338EAF49ADCDF315DAA9CEAC64986E649854229C8B864DA56B18B2E  sim/baseline_closure/irq_test.S
751ACE8AEDCC7493DF7E8EC82922A7BF8D12FB7AAAC6078B7C15426254FE89CE  sim/baseline_closure/wrong_path_side_effect_test.S
DA81BA372C55C2297E24EF6F7629611900C65FEFD9B8B9397F3AE548EC94A33B  sim/baseline_closure/run_baseline_closure.ps1
3FE1120EAA9F1C4AB646618D06B46544380A1AD3D58BCB6356D18B77CCED047F  vivado/ultra_scalar_bht_btb_xc7z020/implement_param_sweep_ooc.tcl
38ED4F3F08B46A1DAFB5AA8A5E73F722C38FAE4B91F04088F583C8B69BC1FA17  vivado/ultra_scalar_bht_btb_xc7z020/run_baseline_closure_vivado.ps1
```

对活动 RTL、测试和构建脚本（排除生成的 VCD/ELF/obj 文件）的容量参数扫描结果为 0：`BRANCH_PREDICTOR_INDEX_W` 和 `BRANCH_PREDICTOR_ENTRIES` 不再出现在活动接口或构建参数中。生成的旧 VCD 仍可能保留历史层次符号，但不属于源码或构建输入。

关键波形入口为 [top_tcm_axi/tb/verilator.vcd](../top_tcm_axi/tb/verilator.vcd)。该 VCD 是实验目录中保留的波形产物，本轮未为重复长测重新生成，故不把它单独作为源码 hash 绑定的 signoff 证据；需要新波形时将 `ENABLE_WAVES=yes` 传给同一仿真脚本即可。

## 3. 配置和实现契约

| 配置 | EXTRA_DECODE_STAGE | SUPPORT_REGFILE_XILINX | SUPPORT_BRANCH_PREDICTION | 状态 |
| --- | ---: | ---: | ---: | --- |
| A0 | 0 | 0 | 0 | predictor-off 对照 |
| A1 | 0 | 0 | 1 | predictor-on 对照 |
| D0 | 1 | 1 | 0 | FPGA 对照 |
| D1 | 1 | 1 | 1 | FPGA 主候选 |

叶级 predictor 的容量为内部 localparam：`BTB_ENTRIES=64`、`INDEX_W=6`、`TAG_W=24`；索引为 `PC[7:2]`，完整 tag 为 `PC[31:8]`。保留 `RAM64X1D`。core/top 不再传递容量参数；core/top 集成默认关闭预测，运行配置显式打开 A1/D1。

## 4. 验证命令和结果

### 4.1 lint、预测器单元和失败退出路径

单元命令：

```powershell
docker run --rm -v "D:\code\FPGA\runs\ultra-top-tcm-bht-btb:/work" ultra-top-tcm:verilator-5.050-systemc-2.3.1a -lc "cd /work/sim/branch_predictor && rm -rf obj && verilator --lint-only --Wno-fatal --top-module riscv_branch_predict -I../../core/riscv ../../core/riscv/riscv_branch_predict.v && verilator --binary --timing --top-module tb_riscv_branch_predict -I../../core/riscv ../../core/riscv/riscv_branch_predict.v tb_riscv_branch_predict.v -Mdir obj && ./obj/Vtb_riscv_branch_predict"
```

证据：[baseline_closure_unit_final.log](baseline_closure_unit_final.log)，末行 `PASS: riscv_branch_predict unit test`，退出码 0。

真实 64 项单元覆盖：

- `update_valid_i=1` 且 update 地址稳定、写时钟沿之前检查 `update_hit_o`；覆盖新分配 miss、同 tag hit、同索引不同 tag 替换 miss、替换后新 tag hit/旧 tag miss和 invalidate 后 miss。
- `0x10` 与 `0x110` 是同索引不同 tag；`0x10` 与 `0x50` 是不同索引；覆盖高位 tag、索引 0 和索引 63。
- BHT 00/01/10/11 的实际转移、00/11 饱和、替换重新初始化；并覆盖 reset、FENCE.I、JAL、独立 lookup/update、同周期读写和 predictor-off 安全输出。

`isa_sim/riscv_main.cpp` 的 ELF 加载失败路径现返回非零。缺失 ELF 的负向检查保留在 [baseline_closure_negative_missing_elf_final.log](baseline_closure_negative_missing_elf_final.log)，其中包含 `Error: Could not open /work/does-not-exist.elf`；该检查的宿主包装器观察到预期非零退出。测试中的 `$fatal(1)` 和 watchdog 也不再以成功退出掩盖失败。

### 4.2 ISA smoke

已有定向 smoke 证据：

- [baseline_closure_d0_isa_smoke.log](baseline_closure_d0_isa_smoke.log)
- [baseline_closure_d1_isa_smoke_final.log](baseline_closure_d1_isa_smoke_final.log)

两份日志均达到程序 signature/停止点；这不是完整 ISA 或形式等价证明。

### 4.3 外部中断

`top_tcm_axi/tb/testbench.h` 的 `set_interrupt(int irq)` 现在写真实顶层 `intr_in`；IRQ 脚本由 `ULTRA_IRQ_TEST` 显式开启，默认关闭，因此 CoreMark 运行保持 IRQ=0。源撤销发生在实际提交 PC 对应的清理点，而不是假定写 CSR 能撤销外部电平。

命令入口：

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\baseline_closure\run_baseline_closure.ps1 -Config A1 -Test IRQ
powershell -ExecutionPolicy Bypass -File .\sim\baseline_closure\run_baseline_closure.ps1 -Config D1 -Test IRQ
```

定向证据：

| 配置 | 屏蔽源 | 使能源 | trap 入口 | signature | 预测/分支交错 | 退出 |
| --- | --- | --- | --- | --- | --- | --- |
| A1 | assert at `0x2024`，withdraw at `0x2028`，handler 次数 0 | assert at `0x2050`，handler `0x209c` withdraw | exception event `0x2050` | `mcause=0x8000000b`，`mepc=0x2050`，masked=0/enabled=1，mip=0 | branch window=1，exact mispredict at `0x2054` | 0 |
| D1 | 同上 | 同上 | 同上 | 同上 | 同上 | 0 |
| D0 | 同上 | 同上 | 同上 | 同上 | 同上 | 0 |

日志：

- [baseline_closure_a1_irq_evidence_final2.log](baseline_closure_a1_irq_evidence_final2.log)
- [baseline_closure_d1_irq_evidence_final2.log](baseline_closure_d1_irq_evidence_final2.log)
- [baseline_closure_d0_irq_evidence_final2.log](baseline_closure_d0_irq_evidence_final2.log)

`mepc=0x2050` 取自 RTL 实际 exception event/CSR 接受边界，不是 IRQ 拉高时刻的猜测。A1/D1 的源撤销分别发生在 handler PC `0x209c`；程序 signature 在 `mret` 后继续到完成点。A1/D1 的 `IRQ_OBS branch_window` 和 `IRQ_OBS branch_mispredict` 均为 1，证明 IRQ 有效期间确实跨过目标分支活动及其误预测；D0 的 predictor-off 分支统计为 `pred_taken=0`，作为对照。

### 4.4 错误路径副作用

命令入口：

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\baseline_closure\run_baseline_closure.ps1 -Config A1 -Test SideEffects
powershell -ExecutionPolicy Bypass -File .\sim\baseline_closure\run_baseline_closure.ps1 -Config D1 -Test SideEffects
```

测试程序把四类副作用拆分到独立分支场景：普通寄存器写、TCM store、合法 CSR 写和测试 MMIO 写；同时提供正确路径正向写入。覆盖 predicted-NT/actual-T 以及训练后 predicted-T/actual-NT。错误路径目标 PC 的提交计数和实际 AXI 写事务均被单独监视。

| 检查项 | A1/D1 证据 |
| --- | --- |
| 错误路径提交 | `nt_wrong[0..3]=0`；`pt_target[0..3]=1`，目标分支确实执行到需要 squash 的在途范围 |
| 寄存器 | `nt_reg=2`，正确路径值；`pt_reg=1`，训练后误路径未污染最终值 |
| TCM | `nt_wrong_tcm=0`，`nt_pos_tcm=0x51aa0001`；`pt_tcm=0x5a550001` |
| CSR | `nt_mscratch=0`、`nt_mtvec=0x2220`；`pt_mscratch=0xa501` |
| MMIO 总线 | 仅两笔完整写事务：`0x10000000/0x11110001` 和 `0x10000004/0x22220001`，各 1 笔，完整 `WSTRB=0xf` |

证据：[baseline_closure_d1_side_effects_evidence_final2.log](baseline_closure_d1_side_effects_evidence_final2.log)、[baseline_closure_d0_side_effects_evidence_final2.log](baseline_closure_d0_side_effects_evidence_final2.log)，以及 A1 的 [baseline_closure_a1_side_effect.log](baseline_closure_a1_side_effect.log)。D1/D0 日志明确 `EXIT_CODE=0`；A1 证据为此前保留的无 FAIL 完成日志。A0/A1/D0/D1 的旧副作用日志均保留，A0/D0 为 predictor-off 对照。

### 4.5 前端握手压力

命令入口：

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\baseline_closure\run_baseline_closure.ps1 -Test Frontend
```

真实 `riscv_fetch` 接口夹具 [tb_frontend_pressure.v](../sim/baseline_closure/tb_frontend_pressure.v) 有界运行三个场景：

1. 下游 stall：输出 PC、指令、`pred_taken` 和预测元数据保持配对；命中日志为 `FRONT_HIT downstream_stall stable_pc=0x00000100 stable_pred=1`。
2. skid buffer 中收到 redirect/correction：旧 `0x100` response 被丢弃，新 `0x600` response 只返回一次；命中日志为 `FRONT_HIT skid_redirect ... dropped=1`。
3. redirect 后旧 outstanding response 晚到：`0x1000/0xaaaaaaaa` 被丢弃，新 `0x1200/0xbbbbbbbb` 返回；命中日志为 `FRONT_HIT outstanding_redirect old_resp_dropped=1`。

证据：[baseline_closure_frontend_pressure_final.log](baseline_closure_frontend_pressure_final.log)，`PASS: frontend pressure test scenarios=3`，退出码 0。日志逐周期记录 request PC、response、输出 PC/指令/预测元数据、branch/redirect/squash/flush。

该夹具的第二场景使用 fetch correction redirect 与 predicted-taken 元数据交错；IRQ 测试另外证明真实外部中断与误预测交错。当前没有把“下游 stall/skid/旧 response”与“真实 IRQ”合成一条更长的单一测试，也没有逐条 retired-PC 白名单，因此这一组合压力项留给独立验收加强，不能扩写成全组合覆盖。

## 5. CoreMark 回归

软件、ELF、编译选项、链接布局、迭代数、TCM 映射和停机边界均冻结。固定 ELF：`benchmarks/coremark-ultra/build/xpack15.2-opt3-iter-516/coremark.elf`；固定停机 PC：`0x202c`（`_halt`）；signature 区间为 `__signature_start` 到 `__signature_end`。

可重跑命令入口：

```powershell
powershell -ExecutionPolicy Bypass -File .\sim\baseline_closure\run_baseline_closure.ps1 -Config All -Test CoreMark
```

本轮/既有最终日志均以同一 ELF 和边界运行；D1 后续重复长测在用户要求后停止，使用已存在的 D1 最终日志，不把保留为 `baseline_closure_d1_coremark_516_final3_aborted.log` 的中断重跑日志当作证据。

逐配置完整比较见 [baseline_closure_results.md](baseline_closure_results.md)。结论为四组短测 CRC 和计数逐项一致。signature 中的 `ERROR! Must execute for at least 10 secs for a valid result!` 是 CoreMark 官方短测有效性提示，不是本轮 CRC 错误；本轮不宣称正式 10 秒成绩。

## 6. Vivado 实现检查

可重跑命令入口：

```powershell
powershell -ExecutionPolicy Bypass -File D:\code\FPGA\vivado\ultra_scalar_bht_btb_xc7z020\run_baseline_closure_vivado.ps1 -Config All
powershell -ExecutionPolicy Bypass -File D:\code\FPGA\vivado\ultra_scalar_bht_btb_xc7z020\run_baseline_closure_vivado.ps1 -Config D1 -DevFrequency
```

本轮实际重跑：D0、D1 在 100 MHz/10 ns OOC 约束；D1 在 80 MHz/12.5 ns OOC 约束。A0/A1 的 post-route 结果只引用历史报告，未覆盖。

约束包括原 `ultra_top_tcm.xdc` 及脚本生成的 clock constraint：

```tcl
create_clock -name clk_i -period <clock_ns> [get_ports clk_i]
set_false_path -from [get_ports {rst_i rst_cpu_i}]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk_i]
```

`check_timing` 的内部 unconstrained endpoints、no_clock、multiple_clock、loops 均为 0；由于这是 OOC 接口级评估，仍有 138 个 input ports 无 input delay、145 个 output ports 无 output delay，适用范围必须保留在报告中。D0/D1 各有 DRC warnings 38、errors 0，主要含现有 RAMB36 异步控制检查警告；不能把 DRC 通过等同于时序通过。

详细数值和资源拆分见 [baseline_closure_results.md](baseline_closure_results.md)。100 MHz 的真实 WNS/TNS 保留为负值；D1 80 MHz 只称为“该约束条件下通过时序的开发频率”，不称板级实测、精确最高频率或已验证 Fmax。

## 7. 仍需独立验收的项目

- CoreMark 正式不少于 10 秒的测量尚未执行；当前仅为固定 516 次短测回归。
- 尚未做形式验证、完整 ISA 证明、板级时钟/IO 实测和完整 SoC 交付验收。
- 前端三个基础压力场景已有命中证据，但真实 IRQ 与 stall/skid/late-response 的统一组合测试及逐条 retired-PC 顺序检查仍可加强。
- 旧 `ΔLUT<=200` 目标仍是例外：本轮不重构硬件，也不把历史 FAIL 改写为 PASS。
