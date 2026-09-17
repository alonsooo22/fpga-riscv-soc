# FPGA CPU / SoC

基于 RISC-V 的 CPU/SoC 开发工程。

2026-09-16新增[两版开发归档](archives/README.md)：SIMD前的E-TCM v4＋C（516次约3.0853 CM/MHz），以及四指令SIMD＋EDAP2（16次约3.3340 CM/MHz，80MHz OOC时序通过）。各自RTL、配置、软件和证据独立保存；归档不改变下述历史accepted基线。

当前版本：**v0.1.0-coremark-baseline**。用户于2026-09-08确认以 CoreMark 已跑通作为当前版本验收条件，接受现有 D1 为开发基线。详细范围和延期项见 [BASELINE.md](BASELINE.md)。

| 目录 | 用途 |
|---|---|
| `runs/ultra-top-tcm-bht-btb` | 活动 RTL、软件、测试和实验报告 |
| `vivado/ultra_scalar_bht_btb_xc7z020` | Vivado 脚本、约束和已有实现报告 |
| `docker/ultra-top-tcm` | 仿真环境与已有运行脚本 |
| `benchmarks/coremark-ultra` | 原有 CoreMark 移植源码 |
| `reports/baseline_acceptance_2026-09-08.md` | 范围调整前的独立验收记录，保留历史事实 |

采用仓库根目录保留现有相对路径。当前开发环境为 Windows、Vivado 2022.2、XC7Z020、Docker/Verilator；部分脚本仍依赖 `D:/code/FPGA` 和本机工具链，新电脑使用前应核对路径。仓库不打包安装工具链、其他参考工程、仿真缓存和 Vivado checkpoint。

主配置 D1：`EXTRA_DECODE_STAGE=1`、`SUPPORT_REGFILE_XILINX=1`、`SUPPORT_BRANCH_PREDICTION=1`。容量固定64项。A1和预测关闭配置保留。

已有运行入口：`runs/ultra-top-tcm-bht-btb/sim/baseline_closure/run_baseline_closure.ps1` 和 `vivado/ultra_scalar_bht_btb_xc7z020/run_baseline_closure_vivado.ps1`。不要为了取得最新文件快照而自动重跑；按改动影响选择必要检查。

