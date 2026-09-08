# Ultra scalar BHT+BTB 验证报告

## 1. 结论摘要

本隔离实验的功能证据为通过：预测器单元测试、基础 ISA smoke、分支/异常/中断定向镜像、CoreMark CRC 检查，以及 A0/A1/D0/D1 四组 Vivado DRC 均通过。预测器关闭时，最终 A0 与隔离基线的 CoreMark 结果逐字段等价；预测器打开时，A1/D1 的错误路径数量显著下降，且没有观察到错误路径提交或 CoreMark 状态破坏。

最终验收结论为 **CONDITIONAL PASS**：LUT 总量增量没有满足严格的 `<=200` 目标（A1 为 `+419`，D1 为 `+320`）。功能和其余已测性能/PPA目标的证据见本报告及 [CoreMark/PPA 报告](branch_predictor_coremark_ppa.md)。

本报告不把短时 CoreMark 运行称为官方 CoreMark 分数；这里的 `CoreMark/MHz` 是固定 516 次迭代下由周期计数推导的比较指标，所有配置的五个 CRC 分量均匹配。

## 2. 隔离范围与实现对象

只在下列两个副本中工作：

- `D:/code/FPGA/runs/ultra-top-tcm-bht-btb`
- `D:/code/FPGA/vivado/ultra_scalar_bht_btb_xc7z020`

参考工程、原始 `runs/ultra-top-tcm` 和原始 Vivado 目录未作为写入目标。Vivado sweep 的 Tcl 明确把 RTL 根目录指向隔离 run；仿真 Docker 只把隔离 run 挂载为 `/work`。

预测器实现位于 `core/riscv/riscv_branch_predict.v`，默认参数为：

```text
SUPPORT_BRANCH_PREDICTION = 0
BRANCH_PREDICTOR_INDEX_W  = 6
```

开启时为 64 项 direct-mapped BTB/BHT；索引为 `PC[7:2]`，完整 tag 为 `PC[31:8]`。条件分支和 JAL 训练，JALR/RET、CSR/trap/xRET/interrupt 不训练第一版表。lookup 为异步组合读，update 为同步写；target/tag/BHT/is_jal 使用显式 `RAM64X1D`，valid 保留为可复位 FF。

## 3. 工具、构建和证据位置

| 项目 | 实际环境 |
| --- | --- |
| RTL 仿真 | Docker image `ultra-top-tcm:verilator-5.050-systemc-2.3.1a` |
| Verilator/SystemC | Verilator 5.050 / SystemC 2.3.1a |
| RISC-V 编译器 | xPack `riscv-none-elf-gcc` 15.2.0-1 |
| 编译优化 | `-O3`，`-march=rv32im_zicsr`，`-mabi=ilp32`；CoreMark 其余选项与隔离基线完全相同 |
| FPGA 工具 | Vivado 2022.2 build 3671981 |
| FPGA 目标 | `xc7z020clg400-1`，`top_tcm_axi`，10.000 ns 时钟约束 |
| CoreMark ELF | `benchmarks/coremark-ultra/build/xpack15.2-opt3-iter-516/coremark.elf` |
| CoreMark signature | `top_tcm_axi/tb/coremark.signature.*.bin` |
| Vivado reports | `D:/code/FPGA/vivado/ultra_scalar_bht_btb_xc7z020/reports/param_sweep/{A0,A1,D0,D1}` |
| 单元测试源 | `sim/branch_predictor/tb_riscv_branch_predict.v` |
| CPU 定向镜像源/ELF | `sim/branch_predictor/branch_redirect_test.S` / `branch_redirect_test.elf` |

CoreMark 仿真构建沿用 `top_tcm_axi/tb/makefile`、`makefile.generate_verilated`、`makefile.build_verilated` 和 `makefile.build_sysc_tb`。通过 `VERILATE_PARAMS` 传入四组顶层参数；`isa_sim/riscv_main.cpp` 在 simulation exit 前调用统计回调，统计只在 `ULTRA_PERF_COUNTERS`/Verilator 路径可见，不进入 Vivado 综合逻辑。

代表性复现命令如下（命令中的路径均在隔离副本内）：

```text
docker run --rm -v D:\code\FPGA\runs\ultra-top-tcm-bht-btb:/work \
  ultra-top-tcm:verilator-5.050-systemc-2.3.1a \
  -lc "cd /work/top_tcm_axi/tb && make clean && make \
  VERILATE_PARAMS='--trace -GEXTRA_DECODE_STAGE=0 -GSUPPORT_REGFILE_XILINX=0 \
  -GSUPPORT_BRANCH_PREDICTION=1 -GBRANCH_PREDICTOR_INDEX_W=6' && \
  ./build/test.x -f /work/benchmarks/coremark-ultra/build/xpack15.2-opt3-iter-516/coremark.elf -t 0"
```

Vivado sweep 使用：

```text
cd D:\code\FPGA\vivado\ultra_scalar_bht_btb_xc7z020
.\run_param_sweep.ps1 -Config All
```

## 4. 单元级验证

单元测试配置使用 `BRANCH_PREDICTOR_INDEX_W=2` 以便在一个小表中快速覆盖别名；CPU/Vivado 配置使用默认 `INDEX_W=6`。该测试同时例化 enabled/disabled 两个实例，最终输出为：

```text
PASS: riscv_branch_predict unit test
```

已执行的自检项：

- reset 后无效项 miss；
- 首次 taken 分配为 weak-taken；
- 首次 not-taken 分配为 strongly-not-taken；
- 2-bit counter 在 `00`/`11` 饱和，不越界；
- JAL 命中恒预测 taken；
- 相同 index 的不同完整 tag 替换，旧项不误命中；
- update 前后的 `update_hit` 与 lookup hit 语义；
- lookup/update 同周期不发生组合 bypass；
- `FENCE.I` 只清 valid，不依赖清空数据 RAM；
- disabled generate 分支所有 lookup/update 输出为安全零值。

默认 64 项、24-bit tag 的结构证据来自源代码的参数化位选和 Vivado A1/D1 的 `u_branch_predict` 实例；最终层次资源也证明 predictor hierarchy 被实际综合，而 A0/D0 中不存在该 hierarchy。

## 5. CPU 集成定向测试

`sim/branch_predictor/branch_redirect_test.S` 覆盖：

- BEQ、BNE、BLT、BGE、BLTU、BGEU 的 taken/not-taken 组合；
- 直接 JAL；
- JALR 间接 call 和 RET；
- `FENCE.I` 后的 direct branch；
- 非法指令同步异常；
- machine software interrupt；
- 通过 `dscratch` checkpoint 输出 `B`、`J`、`E`、`P`。

最终 A0 执行输出：

```text
Memory: 0x2000 - 0x215f ...
Starting from 0x00002000
BJEP
TB: Aborted at 1930 ns
```

`TB: Aborted` 是该已有 SystemC testbench 对 `SIM_CTRL_EXIT` 的结束路径，不是失败退出；进程退出码为 0，且 `P` 通过前置的非法指令和软件中断检查。相同镜像已在 D1 执行通过，输出为 `BJEP` 后正常结束。

基础 ISA smoke 使用隔离 copy 中已有的 `isa_sim/images/basic.elf`，检查序列 1–10 全部通过，随后到达该测试的预期 `TB: Aborted` 结束路径，退出码为 0。

## 6. Predictor-off 等价性

A0 的最终 RTL 与加入预测器前、同一隔离 run 中的 baseline 结果比较如下：

| 项目 | Baseline | A0 | 比较 |
| --- | ---: | ---: | --- |
| `.text` bytes | 18972 | 18972 | identical |
| signature bytes | 4096 | 4096 | identical |
| iterations | 516 | 516 | identical |
| cycles | 200045542 | 200045542 | identical |
| retired instructions | 150778557 | 150778557 | identical |
| scoreboard stall cycles | 12368613 | 12368613 | identical |
| LSU/pipe/div/CSR wait cycles | 0/0/0/0 | 0/0/0/0 | identical |
| branch request events | 18449206 | 18449206 | identical |
| branch redirect cycles | 18449206 | 18449206 | identical |
| branch flush cycles | 36898412 | 36898412 | identical |
| fetch starve cycles | 0 | 0 | identical |
| seedcrc/crclist/crcmatrix/crcstate/crcfinal | e9f5/e714/1fd7/8e3a/e6dc | e9f5/e714/1fd7/8e3a/e6dc | identical |

最终 signature 使用逐字节比较：两者均为 4096 bytes，`DifferingBytes=0`，`FirstDifference=none`。A0 的 Vivado 设计不含 `u_branch_predict`，且 A0 的 LUTRAM 为 0。

## 7. 计数器不变量

CoreMark 运行中增加了 simulation-only branch counters，统计结果满足以下不变量：

- `branch_resolved = branch_conditional + branch_jal + branch_jalr_ret`；
- direct update 数 `= branch_conditional + branch_jal`；
- enabled 时 `branch_btb_hit + branch_btb_miss = direct update 数`；
- `branch_correct + branch_mispredict = direct update 数`；
- JALR/RET 计数不进入 direct BTB update 计数；
- predictor-on 的 branch flush/request 计数显著小于 predictor-off；
- A1/D1 的 CoreMark CRC 与 A0/D0 对应配置一致。

这些是执行后检查，不等同于形式证明。具体计数和派生性能数据在 [branch_predictor_coremark_ppa.md](branch_predictor_coremark_ppa.md)。

## 8. 已执行与未执行的检查

| 检查 | 状态 | 证据/限制 |
| --- | --- | --- |
| Verilator predictor lint-only | PASS | Verilator 5.050，exit code 0 |
| predictor unit self-check | PASS | `tb_riscv_branch_predict.v` 输出 PASS |
| predictor-off CoreMark 等价 | PASS | A0 与隔离 baseline 周期、retired、signature 逐项相同 |
| CoreMark CRC | PASS | 四组 CRC 分量完全一致；运行时长不足官方评分门槛 |
| basic ISA smoke | PASS | 检查 1–10 后预期退出，exit code 0 |
| branch/exception/interrupt directed image | PASS | A0/D1 `BJEP`，exit code 0 |
| `EXTRA_DECODE_STAGE=0/1` alignment | PASS（仿真观察） | A0/A1 与 D0/D1 CoreMark CRC/计数器闭环 |
| Vivado synth/place/route/DRC | PASS | 四组均 `0 Errors; 0 Critical Warnings, 0 Errors` |
| formal properties | 未执行 | 当前环境没有可用 formal 工具 |
| full waveform assertions | 未执行 | 没有把所有错误路径副作用性质转成独立 SVA/formal harness；当前证据为定向镜像、CoreMark 和计数器不变量 |
| standalone backpressure/outstanding/skid stress image | 未执行 | 结构上沿用原有握手/response-drop 控制，CoreMark 覆盖常规 stall；缺少专门压力镜像 |
| external interrupt injection | 未执行 | 定向镜像覆盖 software interrupt，未单独驱动外部 `intr_in` 时序 |
| FPGA board run | 未执行 | 只有 XC7Z020 post-route OOC，没有板级实测 |

残余风险集中在：错误路径无副作用、复杂 backpressure/response-drop 交错，以及外部中断时序尚未有独立断言或压力测试。当前证据足以判定本隔离实验功能通过，但不足以把这些未执行项表述为形式验证通过。

## 9. 验收建议

建议保留该实现作为可回退的实验分支，不直接替换 Ultra baseline。若要提升为新的 baseline，应先由架构负责人决定是否接受 LUT 增量超出 `+200`，并补做错误路径副作用的 waveform/assertion 或 formal 检查；若 LUT 门槛不可放宽，则需要下一轮在不改变预测算法/流水结构约束的前提下优化集成逻辑。
