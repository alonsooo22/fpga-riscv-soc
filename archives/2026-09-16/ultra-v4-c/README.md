# ultra-v4-c

SIMD引入前，兼顾80MHz时序与资源的最佳已测组合：E-TCM v4＋C编译选项。516次167246919cycles、3.085258629CM/MHz，CRC通过；保存原始16次对照便于与SIMD公平比较。

配置见[config.json](config.json)，独立RTL在`rtl/`，原软件源在`software/`，实测ELF、日志和时序在`evidence/`。顶层参数必须显式使用config.json中的值；源码默认值不代表实验开关。

所有性能为周期换算，不是正式10秒成绩或板级Fmax。SIMD版不能沿用标量版516次结果。历史脚本路径仅用于追溯，恢复到新目录后需要调整路径；见[归档总说明](../../README.md)。

本次只复制/校验既有文件，没有重跑仿真或实现。manifest.json记录精确字节哈希及来源。保留原许可证，波形、编译缓存、工具、DCP和bitstream未归档。
