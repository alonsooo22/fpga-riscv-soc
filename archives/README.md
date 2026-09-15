# CPU/SIMD 开发归档

2026-09-16按用户要求保存两版可追溯快照。归档不改变根目录`BASELINE.md`的历史验收决定，也不把SIMD短测标成完整成绩。

| 快照 | 配置 | CoreMark结果 | XC7Z020-1，12.5ns OOC |
|---|---|---|---|
| [ultra-v4-c](2026-09-16/ultra-v4-c/README.md) | SIMD前最佳已测组合：E-TCM v4＋C优化 | 516次：167246919cycles，3.085258629CM/MHz；16次：5186392cycles | 3689LUT/1910FF/4DSP/16BRAM36；WNS0.000ns，hold通过 |
| [ultra-v4-simd-edap2](2026-09-16/ultra-v4-simd-edap2/README.md) | 同v4骨架，四条自定义指令＋预打包双输出软件 | 16次：4799009cycles，3.334021670CM/MHz；五项CRC通过，516次未运行 | 3939LUT/1910FF/6DSP/16BRAM36；WNS+0.013ns，hold通过 |

两版均D1、Xilinx RF、64KiB TCM、full-tag 64-entry BTB/BHT、无RAS。C优化为`-O3 -flto -funroll-loops`，ISA/ABI为`rv32im_zicsr`/`ilp32`。SIMD使用custom-0和`.insn`，不是自动向量化或标准RVV。

每版包含独立RTL、软件源和实测ELF、配置JSON、仿真TB源、关键原始日志与PPA报告、来源和SHA256清单。`common/isa_sim`是两版仿真所需的原有运行库源码，不包含工具安装或编译产物。

用`python archives/verify.py`校验归档字节。`materialize.py`可在指定的新目录恢复原布局；只复制源文件，不编译或仿真。原执行脚本保留于`provenance_scripts`，其中本机路径是历史来源，迁移后须调整；不能直接当作已验证的可移植入口。

不上传波形、缓存、Verilator生成模型、对象库、Vivado DCP或bitstream。PPA报告对应历史实际运行，重新实现可能因工具/布局变化而不同。小型ELF/signature是有意保存的测量输入/证据。
