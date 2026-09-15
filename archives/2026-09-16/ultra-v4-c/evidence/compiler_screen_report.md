# Ultra E-TCM v4 三配置编译器性能筛选

日期：2026-09-15

## 结论

在固定的 E-TCM v4 / D1 / full-tag 64-entry direct-mapped BTB/BHT / no-RAS 硬件上，有限候选中的 C（`-O3 -flto -funroll-loops`）通过 16-iteration 短测和一次 516-iteration 完整测量。C 的短测和完整测量均为最少周期，推荐作为新的软件候选提交决策代理审查；不自动替换 accepted D1、默认固件或 Git tag。

该结论只适用于本轮 R/A/B/C 和固定 CoreMark 工作负载，不能称为 Ultra 的全局最优编译配置。收益是编译器产生的软件差异，不是 CPU RTL 提速或 PPA 结果。

## 固定契约与环境

- 硬件：E-TCM v4、D1、Xilinx RF、full-tag 64-entry direct-mapped BTB/BHT、无 RAS、64 KiB TCM；CPU/SoC RTL 未修改。
- ISA/ABI：`rv32im_zicsr` / `ilp32`；`-mcmodel=medany`、`-msmall-data-limit=0`、freestanding、无 builtin、无 stack protector、无 PIC、函数/数据独立 section。
- CoreMark：现有算法源、performance seeds、`TOTAL_DATA_SIZE=2000`、单线程、TCM、固定 linker layout；短测 16 iterations，完整测量 516 iterations。
- 编译器：`D:\code\FPGA\toolchains\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-gcc.exe`，xPack GNU RISC-V Embedded GCC 15.2.0。
- 仿真容器：`ultra-top-tcm-dev`，镜像 `ultra-top-tcm:verilator-5.050-systemc-2.3.1a`，通过 `D:\code\FPGA\vivado\ultra_bht_btb_followup\scripts\ultra_dev.ps1`；既有 v4 `test_v4_on.x`，未重新编译硬件仿真器。
- 运行时关闭 VCD/FST、shared/corrected observer 和 early-TCM trace；没有生成波形。
- 算法源复制到独立实验目录后未修改；逐文件内容与入口 `D:\code\FPGA\runs\ultra-top-tcm-bht-btb\benchmarks\coremark-ultra` 一致。

候选定义及执行优先级为：R=`-O3`（无 LTO，参考）、B=`-O3 -flto`、A=`-O2 -flto`、C=`-O3 -flto -funroll-loops`。LTO 选项同时出现在各 C/汇编编译和最终 GCC 链接命令中，完整命令见各候选 `build.log`。

## 实际执行

实际运行了四个 16-iteration 短测：R、B、A、C；随后只对短测明显胜出的 C 运行一次 516-iteration 完整测量。历史完整 R 不重跑，直接复用既有 v4 结果；没有运行 A/B 完整测量，没有运行 PGO、profile、RTL、Vivado 或 PPA。

可复用入口：

```powershell
& 'D:\code\FPGA\vivado\ultra_bht_btb_followup\scripts\run_compiler_screen_20260915.ps1' -Action Prepare
& 'D:\code\FPGA\vivado\ultra_bht_btb_followup\scripts\run_compiler_screen_20260915.ps1' -Action BuildShort -Config All
& 'D:\code\FPGA\vivado\ultra_bht_btb_followup\scripts\run_compiler_screen_20260915.ps1' -Action RunShort -Config All
& 'D:\code\FPGA\vivado\ultra_bht_btb_followup\scripts\run_compiler_screen_20260915.ps1' -Action BuildFull -Config C
& 'D:\code\FPGA\vivado\ultra_bht_btb_followup\scripts\run_compiler_screen_20260915.ps1' -Action RunFull -Config C
& 'D:\code\FPGA\vivado\ultra_bht_btb_followup\scripts\run_compiler_screen_20260915.ps1' -Action Summarize
```

脚本在签名输出缺失、仿真非零退出或波形出现时失败退出；短测 16 iterations 的有效 `crcfinal` 是 `0xdd50`，516 iterations 的有效 `crcfinal` 是 `0xe6dc`。其余 CRC 字段均为 `seedcrc=e9f5`、`crclist=e714`、`crcmatrix=1fd7`、`crcstate=8e3a`。

## 结果：短测筛选

周期均为 CoreMark `start_time` 到 `stop_time` 的差值，不是宿主机耗时、仿真总时间或 TB abort 时间。

| 配置 | 选项 | Iterations | cycles | retired | CPI | CM/MHz（周期推导） | .text | CRC | 状态 |
|---|---|---:|---:|---:|---:|---:|---:|---|---|
| R | `-O3` | 16 | 5,322,014 | 4,675,512 | 1.138274054 | 3.006380667 | 18,972 B | `dd50` | PASS |
| B | `-O3 -flto` | 16 | 5,320,503 | 4,598,090 | 1.157111540 | 3.007234466 | 27,288 B | `dd50` | PASS |
| A | `-O2 -flto` | 16 | 5,468,892 | 4,779,281 | 1.144291788 | 2.925638319 | 10,840 B | `dd50` | PASS |
| C | `-O3 -flto -funroll-loops` | 16 | **5,186,392** | 4,589,416 | 1.130076681 | **3.084996275** | 34,792 B | `dd50` | **PASS / short winner** |

C 比 R 少 135,622 cycles（2.548321%）。B 仅少 1,511 cycles（0.028392%），不视为足以取代 C 的明确优胜者；A 虽然 `.text` 最小，但比 R 多 146,878 cycles（2.759820%）。

已有低开销计数如下；这些计数可能重叠，只作伴随证据，不直接相加解释总周期：

| 配置 | scoreboard stall | LSU stall | pipe stall | branch request | branch redirect | branch flush |
|---|---:|---:|---:|---:|---:|---:|
| R | 291,561 | 0 | 0 | 118,323 | 118,323 | 236,646 |
| B | 383,041 | 0 | 0 | 113,134 | 113,134 | 226,268 |
| A | 293,266 | 0 | 0 | 132,122 | 132,122 | 264,244 |
| C | **214,529** | 0 | 0 | 116,932 | 116,932 | 233,864 |

短测只说明 C 同时有较少 retired、较低 CPI 和较少 scoreboard stall；没有新增事件画像，不能据此断言某个具体 load/BTB/调用路径是因果来源。

## 结果：516-iteration 闭合

历史完整 R 的有效计时区间为 `cycle_start=13,738` 至 `cycle_end=171,638,844`，得到 `171,625,106` cycles；退休区间为 `instret_start=11,966` 至 `instret_end=150,790,522`，得到 `150,778,556` retired。该结果按本轮规范复用，未重跑。

C 的新完整运行区间为 `cycle_start=14,502` 至 `cycle_end=167,261,421`，退休区间为 `instret_start=12,793` 至 `instret_end=148,013,491`。

| 配置 | 选项 | Iterations | cycles | retired | CPI | CM/MHz（周期推导） | .text | CRC | 状态 |
|---|---|---:|---:|---:|---:|---:|---:|---|---|
| 历史 R | `-O3` | 516 | 171,625,106 | 150,778,556 | 1.138259382 | 3.006553132 | 18,972 B | 历史有效 | REUSED reference |
| C | `-O3 -flto -funroll-loops` | 516 | **167,246,919** | **148,000,698** | **1.130041420** | **3.085258629** | 34,792 B | `e6dc` | **PASS / winner confirmed** |

C 相对历史 R：

- cycles 减少 4,378,187（2.551018%）；每 iteration 为 324,121.936047 cycles，历史 R 为 332,606.794574 cycles。
- retired 减少 2,777,858（1.842343%）。
- CPI 从 1.138259382 降到 1.130041420，下降约 0.721976%。因此改善是 retired 减少与 CPI 下降共同作用，不能只归因于其中一项。
- 516 次 C 的 `crcfinal=e6dc`，签名和仿真退出码通过；CoreMark 输出的“至少 10 秒”提示是仿真计时器的标准墙钟检查，历史 R 也有相同性质。本轮报告使用硬件 cycle 区间推导 CM/MHz，不把它称为 10 秒正式墙钟成绩。

完整测量低开销计数对照：

| 配置 | scoreboard stall | LSU stall | pipe stall | branch request | branch redirect | branch flush | fetch starve |
|---|---:|---:|---:|---:|---:|---:|---:|
| 历史 R | 9,402,634 | 未在历史摘要中单独显示为非零 | 未在历史摘要中单独显示为非零 | 3,814,648 | 参照日志未单独用于本表 | 7,629,296 | 参照日志未单独用于本表 |
| C | 6,918,569 | 0 | 0 | 3,768,667 | 3,768,667 | 7,537,334 | 0 |

C 的 scoreboard stall 比历史 R 少 2,484,065（26.418821%），branch request 少 45,981（1.205380%）。计数支持“编译结果改变动态指令/依赖等待组成”的事实，但没有足够证据把收益归因到某一个微架构路径；本轮未采集 load/BTB 细分。

## 代码与 TCM 容量

C 的短 ELF 与完整 ELF 的代码段布局相同，反汇编主体除 ELF 文件头路径外无差异；`.data` 初值因 `seed4_volatile=ITERATIONS` 按工作量改变，故仍按契约对完整 ELF 做了实测。

完整 C 的实际加载布局为：`.text=34,792 B @ 0x2000`，`.rodata=3,016 B @ 0xa7e8`，`.data=8 B @ 0xb3b0`，`.bss=2,104 B @ 0xb3b8`，`.signature=4,096 B @ 0xe000`。仿真显示加载范围为 `.text 0x2000–0xa7e7`、`.bss 0xb3b8–0xbbef`、signature `0xe000–0xefff`，未与 signature 重叠；链接器仍为原 64 KiB TCM，未扩大容量、未改变栈/工作区配置。完整 `size -A` 和 `readelf -S` 保存在 C full build 目录。

相对历史 R，C 的 `.text` 增加 15,820 B（83.386043%），但取得 2.551018% 周期收益；这是本轮最重要的代码尺寸/性能权衡。A 的小代码尺寸没有转化为性能优势。B 的代码增长明显、短测仅有边际周期差，未进入完整测量。

## 决策回答

1. C 在短测和完整 516 测量中都是最少周期，排序一致。
2. C 的改善来自 retired 减少和 CPI 下降共同变化；现有计数只支持动态组成变化，不支持更细的机制归因。
3. C 的展开使 `.text` 从 18,972 B 增至 34,792 B，增长明显；在不改变 64 KiB TCM 的前提下仍可加载，并取得可信的完整周期改善。
4. A 的 `.text` 最小但周期最慢，且 CPI/retired 均未优于 R。
5. B 的短测几乎与 R 持平，不能用这点边际差异抵消更大的代码体积，也没有必要为它追加完整运行。
6. 推荐 C 作为软件候选，由决策代理独立验收；不修改 accepted D1 或默认固件。
7. 若下一轮需要继续分析，应只对 C 做聚焦 load/BTB profile，并以完整结果为输入；本轮没有开展该 profile。

## 证据位置与限制

- 汇总 CSV：`D:\code\FPGA\vivado\ultra_bht_btb_followup\reports\compiler_screen_20260915\compiler_screen_results.csv`
- 可复用脚本：`D:\code\FPGA\vivado\ultra_bht_btb_followup\scripts\run_compiler_screen_20260915.ps1`
- 短测日志/signature：本目录下 `short_R.*`、`short_A.*`、`short_B.*`、`short_C.*`。
- 完整 C 日志/signature：本目录下 `full_C.*`。
- 各候选 ELF、map、反汇编、section、symbol 和 build log：`D:\code\FPGA\vivado\ultra_bht_btb_followup\sim\compiler_screen_20260915\build\short\` 与 `...\build\full\C\`。
- 构建清单：`D:\code\FPGA\vivado\ultra_bht_btb_followup\sim\compiler_screen_20260915\build_manifest.csv`。

本轮是四个预先指定选项的有限筛选，不是全局编译器搜索；短测仅用于低成本排序，完整 C 才是闭合结果。未执行 Vivado/PPA，因此不能由本轮推断硬件资源或频率变化。
