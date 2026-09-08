param(
    [Parameter(Mandatory = $true)]
    [string]$RunRoot,
    [Parameter(Mandatory = $true)]
    [string]$ToolchainRoot,
    [ValidateSet('A', 'B', 'C', 'D', 'All')]
    [string]$Config = 'All',
    [ValidateRange(1, 1000000)]
    [int]$Iterations = 516,
    [ValidateRange(1, 10000000000)]
    [long]$CoremarkFrequencyHz = 100000000,
    [string]$Image = 'ultra-top-tcm:verilator-5.050-systemc-2.3.1a'
)

$ErrorActionPreference = 'Stop'
$Builder = Join-Path $PSScriptRoot 'build-coremark-xpack.ps1'
$RunRoot = (Resolve-Path $RunRoot).Path
$ToolchainRoot = (Resolve-Path $ToolchainRoot).Path
$ExperimentRoot = Join-Path $RunRoot 'experiments\param_sweep\coremark'

if (-not (Test-Path -LiteralPath $Builder)) {
    throw "xPack CoreMark builder not found: $Builder"
}
if (-not (Test-Path -LiteralPath (Join-Path $RunRoot 'top_tcm_axi\tb\makefile.generate_verilated'))) {
    throw "Ultra top_tcm_axi testbench not found under $RunRoot"
}

$Configs = [ordered]@{
    A = @{ ExtraDecode = 0; XilinxRegfile = 0 }
    B = @{ ExtraDecode = 1; XilinxRegfile = 0 }
    C = @{ ExtraDecode = 0; XilinxRegfile = 1 }
    D = @{ ExtraDecode = 1; XilinxRegfile = 1 }
}
$Selected = if ($Config -eq 'All') { @('A', 'B', 'C', 'D') } else { @($Config) }

# Build one identical xPack GCC 15.2 -O3 image. The RTL parameter sweep must
# not change the software input to any of the four runs.
& $Builder -RunRoot $RunRoot -ToolchainRoot $ToolchainRoot -OptLevel 3 -Iterations $Iterations
if ($LASTEXITCODE -ne 0) {
    throw "xPack CoreMark build failed with exit code $LASTEXITCODE"
}

$ElfRelative = "benchmarks/coremark-ultra/build/xpack15.2-opt3-iter-$Iterations/coremark.elf"
$ElfHost = Join-Path $RunRoot ($ElfRelative -replace '/', '\')
if (-not (Test-Path -LiteralPath $ElfHost)) {
    throw "Expected CoreMark ELF was not produced: $ElfHost"
}

New-Item -ItemType Directory -Path $ExperimentRoot -Force | Out-Null
$Mount = "type=bind,source=$RunRoot,target=/workspace/ultra-riscv"
$Common = @(
    'run', '--rm',
    '--mount', $Mount,
    '--workdir', '/workspace/ultra-riscv/top_tcm_axi/tb',
    $Image
)

$Rows = @()
foreach ($Name in $Selected) {
    $Spec = $Configs[$Name]
    $HostDir = Join-Path $ExperimentRoot $Name
    New-Item -ItemType Directory -Path $HostDir -Force | Out-Null
    $OutputLog = Join-Path $HostDir 'run.log'
    $Extra = [int]$Spec.ExtraDecode
    $Regfile = [int]$Spec.XilinxRegfile

    $Command = @"
set -e
export ENABLE_WAVES=no
EXP=/workspace/ultra-riscv/experiments/param_sweep/coremark/$Name
make -C /workspace/ultra-riscv/isa_sim lib
make -f makefile.generate_verilated CORE=riscv \
  OUTPUT_DIR="`$EXP/verilated" \
  VERILATE_PARAMS="--trace -Wno-fatal -DULTRA_PERF_COUNTERS -GEXTRA_DECODE_STAGE=$Extra -GSUPPORT_REGFILE_XILINX=$Regfile"
make -f makefile.build_verilated \
  SRC_DIR="`$EXP/verilated/" \
  OBJ_DIR="`$EXP/obj_verilated/" \
  LIB_DIR="`$EXP/lib/"
make -f makefile.build_sysc_tb \
  OBJ_DIR="`$EXP/obj_tb/" \
  EXE_DIR="`$EXP/run/" \
  VERILATED_DIR="`$EXP/verilated" \
  clean
make -f makefile.build_sysc_tb \
  OBJ_DIR="`$EXP/obj_tb/" \
  EXE_DIR="`$EXP/run/" \
  VERILATED_DIR="`$EXP/verilated" \
  EXTRA_CFLAGS="-I`$EXP/verilated" \
  LIB_PATH="`$EXP/lib ../../isa_sim"
ELF=/workspace/ultra-riscv/$($ElfRelative.Replace('\','/'))
HALT_PC=0x`$(riscv64-unknown-elf-nm "`$ELF" | grep _halt | cut -c1-8)
TEXT_BYTES=`$(riscv64-unknown-elf-size -A "`$ELF" | awk '`$1==".text" {print `$2}')
echo "RUN_CONFIG      : xPack GCC 15.2.0-O3 Ultra config $Name"
echo "text_bytes      : `$TEXT_BYTES"
"`$EXP/run/test.x" -f "`$ELF" -r "`$HALT_PC" -p "`$EXP/coremark.signature.bin" -j __signature_start -k __signature_end
strings -n 1 "`$EXP/coremark.signature.bin"
"@

    Write-Host "=== CoreMark parameter sweep ${Name}: EXTRA_DECODE_STAGE=$Extra, SUPPORT_REGFILE_XILINX=$Regfile ==="
    $Output = @(& docker @Common -lc $Command 2>&1)
    $DockerExitCode = $LASTEXITCODE
    $Text = $Output -join [Environment]::NewLine
    $Text | Set-Content -LiteralPath $OutputLog -Encoding UTF8
    Write-Output $Text
    if ($DockerExitCode -ne 0) {
        throw "CoreMark parameter sweep $Name failed with exit code $DockerExitCode. See $OutputLog"
    }

    $Get = {
        param([string]$Pattern, [string]$Label)
        $Match = [regex]::Match($Text, $Pattern)
        if (-not $Match.Success) { throw "Missing $Label in $OutputLog" }
        return [decimal]$Match.Groups[1].Value
    }
    $CycleStart = & $Get 'cycle_start\s*:\s*(\d+)' 'cycle_start'
    $CycleEnd = & $Get 'cycle_end\s*:\s*(\d+)' 'cycle_end'
    $InstretStart = & $Get 'instret_start\s*:\s*(\d+)' 'instret_start'
    $InstretEnd = & $Get 'instret_end\s*:\s*(\d+)' 'instret_end'
    $RunIterations = & $Get 'Iterations\s*:\s*(\d+)' 'Iterations'
    $TextBytes = & $Get 'text_bytes\s*:\s*(\d+)' 'text_bytes'

    $Cycles = $CycleEnd - $CycleStart
    $Retired = $InstretEnd - $InstretStart
    if ($Cycles -le 0 -or $Retired -le 0 -or $RunIterations -le 0) {
        throw "Invalid CoreMark counters for $Name in $OutputLog"
    }
    $InstructionsPerIteration = $Retired / $RunIterations
    $CyclesPerIteration = $Cycles / $RunIterations
    $Cpi = $Cycles / $Retired
    $CmPerMHz = $RunIterations * 1000000 / $Cycles
    $CmPerSecondAt100MHz = $CmPerMHz * ($CoremarkFrequencyHz / 1000000)
    $CrcPass = $Text -match 'seedcrc\s*:\s*0xe9f5' -and
        $Text -match '\[0\]crclist\s*:\s*0xe714' -and
        $Text -match '\[0\]crcmatrix\s*:\s*0x1fd7' -and
        $Text -match '\[0\]crcstate\s*:\s*0x8e3a' -and
        $Text -match 'e6dc'

    $Rows += [pscustomobject]@{
        Config = $Name
        DecodeStage = $Extra
        XilinxRegfile = $Regfile
        Compiler = 'xPack GCC 15.2.0 -O3'
        TextBytes = [long]$TextBytes
        Iterations = [long]$RunIterations
        CycleStart = [long]$CycleStart
        CycleEnd = [long]$CycleEnd
        Cycles = [long]$Cycles
        InstretStart = [long]$InstretStart
        InstretEnd = [long]$InstretEnd
        RetiredInstructions = [long]$Retired
        InstructionsPerIteration = [double]$InstructionsPerIteration
        CyclesPerIteration = [double]$CyclesPerIteration
        CPI = [double]$Cpi
        CoreMarkPerMHz = [double]$CmPerMHz
        CoreMarkPerSecondAt100MHz = [double]$CmPerSecondAt100MHz
        CRC = if ($CrcPass) { 'PASS' } else { 'FAIL' }
        Log = $OutputLog
    }
}

$CsvPath = Join-Path $ExperimentRoot 'coremark_metrics.csv'
$JsonPath = Join-Path $ExperimentRoot 'coremark_metrics.json'
$Rows | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
$Rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $JsonPath -Encoding UTF8

Write-Output "CoreMark metrics written to $CsvPath"
$Rows | Format-Table Config, DecodeStage, XilinxRegfile, TextBytes, Iterations, Cycles, RetiredInstructions, InstructionsPerIteration, CyclesPerIteration, CPI, CoreMarkPerMHz, CRC
