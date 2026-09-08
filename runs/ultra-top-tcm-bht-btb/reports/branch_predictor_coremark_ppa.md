# Ultra scalar BHT+BTB CoreMark 与 PPA 报告

## 1. 测量口径

所有软件结果来自同一个隔离 CoreMark ELF：

```text
benchmarks/coremark-ultra/build/xpack15.2-opt3-iter-516/coremark.elf
```

CoreMark 源码、链接脚本、计时区间和编译选项没有因预测器改变。编译器是 xPack `riscv-none-elf-gcc` 15.2.0-1，优化为 `-O3`，ISA/ABI 为 `-march=rv32im_zicsr -mabi=ilp32`，另沿用原有 freestanding、section 和 `top_tcm_axi` 选项。`TOTAL_DATA_SIZE=2000`、performance seeds 和约 516 iterations 保持一致。

四组配置为：

| 配置 | `EXTRA_DECODE_STAGE` | `SUPPORT_REGFILE_XILINX` | `SUPPORT_BRANCH_PREDICTION` |
| --- | ---: | ---: | ---: |
| A0 | 0 | 0 | 0 |
| A1 | 0 | 0 | 1 |
| D0 | 1 | 1 | 0 |
| D1 | 1 | 1 | 1 |

### CoreMark 主结果

| 配置 | `.text` | iterations | cycles | retired | instr/iter | cycles/iter | CPI | CoreMark/MHz |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A0 | 18972 | 516 | 200045542 | 150778557 | 292206.505814 | 387685.158915 | 1.326750607 | 2.579412642 |
| A1 | 18972 | 516 | 170776426 | 150778557 | 292206.505814 | 330962.065891 | 1.132630723 | 3.021494313 |
| D0 | 18972 | 516 | 218494748 | 150778556 | 292206.503876 | 423439.434109 | 1.449110230 | 2.361612829 |
| D1 | 18972 | 516 | 174591074 | 150778556 | 292206.503876 | 338354.794574 | 1.157930402 | 2.955477552 |

计算式为 `CoreMark/MHz = 516 × 10^6 / cycles`。A1 相对 A0 的 CoreMark/MHz 提升为 `17.1389%`，D1 相对 D0 提升为 `25.1466%`。A0/A1 的 retired 数保持一致，D0/D1 各自保持一致；D 组比 A 组少 1 条 retired instruction 是已有 `EXTRA_DECODE_STAGE=1` 配置的基线差异，不是 predictor on/off 差异。

### CRC 与非分支 stall 计数

四组均得到完全相同的组件 CRC：

```text
seedcrc=e9f5  crclist=e714  crcmatrix=1fd7  crcstate=8e3a  crcfinal=e6dc
```

四组 scoreboard stall 均为 `12368613`，即 `23970.180233 cycles/iteration`；LSU、pipe、div、CSR wait 均为 0，fetch starve 均为 0。A0 的最终 signature 与隔离 baseline signature 均为 4096 bytes，逐字节比较结果为 `DifferingBytes=0`、`FirstDifference=none`。

## 2. 分支计数器结果

计数器由执行级有效解析记录和预测器 update 记录产生，且只作为仿真观测，不进入 Vivado 综合。direct 数为 `conditional + JAL`；predictor-off 时 `BTB miss` 是对没有预测的 direct 事件的记账，不能理解为真实表查找发生了 29.88 M 次后的硬件命中率。

| 配置 | resolved | conditional | JAL | JALR/RET | BTB hit | BTB miss | pred taken | correct | mispredict | direction accuracy |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A0 | 30591841 | 27334861 | 2548345 | 708635 | 0 | 29883206 | 0 | 12137700 | 17745506 | 40.617128%* |
| A1 | 30591829 | 27334849 | 2548345 | 708635 | 27680547 | 2202647 | 16868947 | 26776118 | 3107076 | 89.602597% |
| D0 | 30591841 | 27334861 | 2548345 | 708635 | 0 | 29883206 | 0 | 12137700 | 17745506 | 40.617128%* |
| D1 | 30591829 | 27334849 | 2548345 | 708635 | 27680547 | 2202647 | 16868947 | 26776118 | 3107076 | 89.602597% |

`*` A0/D0 的百分比只是把 predictor-off 的默认 not-taken 与 actual direction 做比较，不是启用 BTB 后的预测器精度。

开启预测器时，direct update 数为 `29883194`，其中 BTB hit 率为 `92.629145%`；`correct + mispredict = 29883194`。关闭预测器时 direct 数为 `29883206`，所有事件都记为 miss。计数不变量 `resolved = conditional + JAL + JALR/RET`、`direct = conditional + JAL` 均成立。

## 3. 分支惩罚效果

| 配置 | branch request events | redirect cycles | flush cycles | flush/iter |
| --- | ---: | ---: | ---: | ---: |
| A0 | 18449206 | 18449206 | 36898412 | 71508.550388 |
| A1 | 3814648 | 3814648 | 7629296 | 14785.457364 |
| D0 | 18449206 | 18449206 | 36898412 | 71508.550388 |
| D1 | 3814648 | 3814648 | 7629296 | 14785.457364 |

预测器开启后的 flush/request 相对关闭状态减少：

```text
1 - 7629296 / 36898412 = 79.323511%
```

这超过最低 60% 和期望 66.5% 的目标。性能提升来自 direct branch/JAL 正确预测后不再走 front-end redirect/squash；JALR/RET、CSR 和异常仍走原有执行级 redirect。

## 4. Vivado post-route 结果

Vivado 版本为 2022.2 build 3671981，器件为 `xc7z020clg400-1`，顶层为 `riscv_tcm_top`，同一 10.000 ns 时钟约束和同一 OOC synth/opt/place/phys_opt/route 流程。四组 DRC 均为 `0 Errors; 0 Critical Warnings, 0 Errors`。

### 顶层资源与 timing

| 配置 | WNS (ns) | TNS (ns) | first critical delay (ns) | Fmax estimate (MHz) | LUT | LUT logic | LUTRAM | FF | BRAM36 | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A0 | -3.672 | -1918.984 | 13.569 | 73.697398 | 3661 | 3661 | 0 | 2666 | 16 | 4 |
| A1 | -3.518 | -1956.518 | 13.330 | 75.018755 | 4080 | 3967 | 113 | 2803 | 16 | 4 |
| D0 | -2.566 | -821.001 | 12.370 | 80.840744 | 3421 | 3165 | 256 | 1752 | 16 | 4 |
| D1 | -1.815 | -519.395 | 11.685 | 85.579803 | 3741 | 3372 | 369 | 1877 | 16 | 4 |

Fmax 是从 post-route 首条最差 setup path 的 `Data Path Delay` 计算的估计值：`Fmax_estimate = 1000 / delay_ns`。它没有把这个设计已有的负 WNS 隐藏掉：四组在 100 MHz 约束下仍有 setup violation，预测器 on/off 的相对比较是 A1 相对 A0、D1 相对 D0 的退化/改善。

### 成对增量

| 对比 | LUT 增量 | FF 增量 | LUTRAM 增量 | BRAM 增量 | DSP 增量 | Fmax 变化 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A1 - A0 | +419 | +137 | +113 | 0 | 0 | +1.794% |
| D1 - D0 | +320 | +125 | +113 | 0 | 0 | +5.860% |

预测器打开后，A1/D1 hierarchy 均报告：

```text
u_core/u_branch_predict : 200 total LUT = 87 LUT logic + 113 LUT memory,
                          64 FF, 0 BRAM, 0 DSP
```

A0/D0 不含 `u_branch_predict` hierarchy，且 predictor-off 顶层 LUTRAM 为 0。顶层总 LUT 增量大于 predictor hierarchy 的 200 LUT，是因为 fetch/issue/exec 的预测 metadata、mispredict correction、update 记录和连接逻辑也产生了资源；这也是严格 LUT 目标失败的实际原因，不能只用 hierarchy 内部数字代替成对总量。

### 最差路径

首条最差路径取自各配置的 `critical_paths.rpt`：

| 配置 | 起点 | 终点 | data delay | logic delay | route delay | logic levels |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| A0 | `u_tcm/u_ram/ram_reg_3_2/CLKBWRCLK` | `u_core/u_lsu/mem_data_wr_q_reg[4]/D` | 13.569 ns | 4.765 ns | 8.804 ns | 14 (`CARRY4=1 LUT3=2 LUT5=1 LUT6=8 MUXF7=1 MUXF8=1`) |
| A1 | `u_tcm/u_ram/ram_reg_1_3/CLKBWRCLK` | `u_core/u_fetch/branch_pc_q_reg[5]/D` | 13.330 ns | 5.053 ns | 8.277 ns | 13 (`CARRY4=2 LUT3=1 LUT5=2 LUT6=6 MUXF7=1 MUXF8=1`) |
| D0 | `u_tcm/u_ram/ram_reg_2_3/CLKARDCLK` | `u_core/u_decode/buffer_q_reg[44]_replica/D` | 12.370 ns | 4.518 ns | 7.852 ns | 11 (`CARRY4=2 LUT4=1 LUT5=1 LUT6=7`) |
| D1 | `u_dmux/tcm_access_q_reg/C` | `u_core/u_decode/buffer_q_reg[36]/D` | 11.685 ns | 3.497 ns | 8.188 ns | 18 (`CARRY4=7 LUT2=1 LUT4=2 LUT5=3 LUT6=5`) |

A1 的最差 endpoint 已落在 `u_core/u_fetch/branch_pc_q_reg[5]/D`，因此预测 next-PC 相关寄存器路径确实出现在首条 critical path 中，但其 data delay 比 A0 的首条路径小 `0.239 ns`，估算 Fmax 没有下降。Vivado 前 20 条 critical path 的层次文本没有直接出现 `u_branch_predict` 单元名；D1 首条最差路径在 decode buffer，不是 predictor hierarchy。最差 1000 条路径的逻辑级分布最大列为 A0/A1=20、D0/D1=19，这与首条路径的实际 logic levels 不矛盾。

## 5. 指标判定

| 目标 | 实测 | 判定 |
| --- | --- | --- |
| branch flush 至少减少 60%，期望 >=66.5% | `79.323511%` | PASS |
| Config A CoreMark/MHz >=2.94 | A1 `3.021494313` | PASS |
| post-route Fmax 下降 <=5% | A1 +1.794%，D1 +5.860%（均改善） | PASS |
| LUT 增加 <=200 | A1 +419，D1 +320 | FAIL |
| FF 增加 <=150 | A1 +137，D1 +125 | PASS |
| LUTRAM 正确推断 | A1/D1 predictor hierarchy 113 LUTRAM | PASS |
| BRAM 增加为 0 | A1/D1 相对对应 off 均 +0；总量 16 BRAM36 | PASS |
| DSP 增加为 0 | A1/D1 相对对应 off 均 +0；总量 4 DSP | PASS |
| Actual CoreMark/s 至少提高 10% | A1/A0 +19.239%，D1/D0 +32.483% | PASS |
| CoreMark/s/LUT 不下降 | A1/A0 +6.994%，D1/D0 +21.151% | PASS |

按成对 post-route Fmax 估计，Actual CoreMark/s 为：

| 配置 | Actual CoreMark/s | CoreMark/s/LUT |
| --- | ---: | ---: |
| A0 | 190.096000 | 0.051924611 |
| A1 | 226.668742 | 0.055556064 |
| D0 | 190.914538 | 0.055806647 |
| D1 | 252.929187 | 0.067610047 |

这些 Actual CoreMark/s 是 `CoreMark/MHz × Fmax_estimate` 的工程比较值，不是板级实测，也不是官方 CoreMark 发布分数。

## 6. 资源与性能结论

预测器数据阵列最终使用显式 `RAM64X1D`，Vivado 将其放入 distributed RAM/LUTRAM；没有新增 BRAM 或 DSP。正确预测静默使 branch flush 从 `71508.550388` 降到 `14785.457364 cycles/iteration`，周期下降与 CoreMark/MHz 提升一致。代价是完整 tag、valid、预测元数据、执行级 update 记录以及 next-PC/mispredict 连接带来的顶层 LUT 增量，超出本轮 `+200` 严格门槛。

因此本轮推荐结论为 **CONDITIONAL PASS**：功能证据和性能方向满足要求，LUT 目标不满足；是否接受应由架构验收决定，不建议在未处理该 PPA 例外前把它替换为新的 Ultra baseline。
