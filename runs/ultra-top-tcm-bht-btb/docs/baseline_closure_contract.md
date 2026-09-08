# Ultra scalar BHT+BTB 开发基线闭合契约

## 1. 本轮目的与边界

本轮目标是把上一轮“功能正确但验证缺口未闭合”的 BHT+BTB 实验整理成可独立验收的 CPU 开发基线。工作范围只包括：容量/配置收敛、预测器单元测试有效性、外部中断仿真注入、错误路径副作用验证、前端握手压力验证、固定 CoreMark 回归和 Vivado 时序口径修正。

本轮不实施 Cache、NPU、RAS、GShare、双发射、紫光迁移或其他性能优化；不修改 LSU、TCM/AXI、forwarding、scoreboard、流水级、异常契约、CoreMark 软件、编译器选项、链接布局和 benchmark 计时边界。上一轮 `ΔLUT<=200` 未满足的事实保持为历史例外，不通过重构硬件或改写报告消除。

工作目录仍为：

```text
D:/code/FPGA/runs/ultra-top-tcm-bht-btb
D:/code/FPGA/vivado/ultra_scalar_bht_btb_xc7z020
```

Docker 只允许挂载第一个目录到 `/work`。references、原始 `runs/ultra-top-tcm` 和原始 Vivado 工程只读。

## 2. 固定实现契约

预测器保持上一轮批准的算法和表结构：

```text
64-entry direct-mapped BTB
64-entry 2-bit BHT
index = PC[7:2]
tag   = PC[31:8]
```

`BRANCH_PREDICTOR_INDEX_W` 从所有 core、top、脚本、构建命令和单元测试中删除；它不再是公共参数。模块内部只保留：

```verilog
localparam integer INDEX_W = 6;
localparam integer BTB_ENTRIES = 64;
localparam integer TAG_W = 24;
```

`SUPPORT_BRANCH_PREDICTION` 继续是公共开关：core/top 集成默认值为 0，叶级 predictor 模块保留其原有库默认值 1；A1/D1 运行时显式为 1。表数据保留显式 `RAM64X1D`，valid 仅使用可复位状态。reset/FENCE.I 清 valid；lookup 需要 valid 与完整 tag；update 为异步观察、时钟沿同步写入，不能把新写入组合旁路到 lookup。

预测范围不变：BEQ/BNE/BLT/BGE/BLTU/BGEU 和 JAL。JALR/RET、CSR/trap/xRET、interrupt 不进入第一版 predictor update。

## 3. 四组配置

| 配置 | `EXTRA_DECODE_STAGE` | `SUPPORT_REGFILE_XILINX` | 预测器 | 用途 |
| --- | ---: | ---: | ---: | --- |
| A0 | 0 | 0 | 0 | predictor-off 对照 |
| A1 | 0 | 0 | 1 | predictor-on 对照 |
| D0 | 1 | 1 | 0 | FPGA 开发基线对照 |
| D1 | 1 | 1 | 1 | 本地 FPGA 主候选 |

CoreMark 固定使用约 516 iterations、`TOTAL_DATA_SIZE=2000`、performance seeds、原始计时区间和原始 ELF。开发频率不由历史单条 data-path delay 倒数冒充；本轮报告将单独记录约束、setup/hold、clock 和 unconstrained-path 检查，并把结果称为“该约束条件下通过时序的开发频率”。

## 4. 验证契约

### 预测器单元

测试必须例化真实 64 项实现，并在 update_valid=1、地址稳定、写时钟沿之前检查 `update_hit_o`。必须命中：新分配 miss、同 tag update hit、同 index 不同 tag 替换 miss、替换后新 tag hit/旧 tag miss、invalidate 后 miss、index 0/index 63 独立寻址、0x10/0x110 高位 tag 冲突、0x10/0x50 不冲突、BHT `00/01/10/11` 状态转换/饱和、JAL、FENCE.I、独立 lookup/update、同周期读写、disabled 安全输出。失败或 watchdog 超时必须以非零退出码结束。

### 外部中断

仿真 testbench 的 `set_interrupt(int irq)` 必须驱动真实顶层 `intr_in`，而非空函数或软件写 `mip` 替代。专用测试模式默认关闭，CoreMark 的 IRQ 维持 0。测试覆盖 enable/屏蔽、真实电平撤销、trap 入口 `mcause/mepc`、mret 恢复、与预测分支/误预测邻近交错，并由提交观测证明恢复顺序。中断接受点的 `mepc` 以 RTL 实际定义为准。

### 错误路径副作用

分别测试 predicted-NT/actual-T 和 trained-predicted-T/actual-NT；每种场景独立放置 register write、TCM store、合法 CSR write、测试 MMIO write，并有正确路径正向对照。MMIO 监视器检查实际总线写事务与写计数。验证目标是错误路径进入在途后被 squash，且不提交、不写寄存器、不写内存、不写 CSR、不产生 MMIO 事务。

### 前端握手

在真实 core fetch/response/accept 接口上构造有界场景：downstream stall、skid buffer + redirect、旧 outstanding response 在 redirect 后返回并丢弃，以及这些场景与误预测/外部中断交错。夹具记录 request PC、response 归属、pred_taken、redirect/correction PC 和提交 PC，检查无丢失、重复提交或旧响应执行；每个场景必须有命中计数/日志证据。

## 5. 验收与交接规则

先 lint，再 unit/directed/ISA smoke，再四组 CoreMark，最后至少重跑 D0/D1 的 Vivado implementation；A0/A1 的历史 post-route 结果保留为历史引用，若本轮重跑则明确标注。最终交付必须分开陈述：

- 功能闭合状态；
- CoreMark 回归状态；
- Vivado 实现和时序状态；
- 未执行检查与残余风险；
- 旧 LUT 目标例外。

缺少关键验证时标为“待闭合候选”；发现功能错误为 FAIL。只有功能检查、回归差异解释和证据路径齐全，才能建议 D1 作为后续本地 FPGA 开发基线；不得声称整个 SoC 或比赛交付已完成。
