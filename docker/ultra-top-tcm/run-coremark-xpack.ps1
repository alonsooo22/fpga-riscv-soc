param(
    [Parameter(Mandatory = $true)]
    [string]$RunRoot,
    [Parameter(Mandatory = $true)]
    [string]$ToolchainRoot,
    [ValidateRange(1, 1000000)]
    [int]$SmokeIterations = 476,
    [ValidateRange(1, 10000000000)]
    [long]$CoremarkFrequencyHz = 100000000,
    [ValidateSet(2, 3)]
    [int]$OptLevel = 2,
    [switch]$Sweep,
    [string]$Image = 'ultra-top-tcm:verilator-5.050-systemc-2.3.1a'
)

$ErrorActionPreference = 'Stop'
$Builder = Join-Path $PSScriptRoot 'build-coremark-xpack.ps1'
if (-not (Test-Path -LiteralPath $Builder)) {
    throw "xPack CoreMark builder not found: $Builder"
}
if (-not (Test-Path -LiteralPath $ToolchainRoot)) {
    throw "xPack toolchain not found: $ToolchainRoot"
}

$mount = "type=bind,source=$RunRoot,target=/workspace/ultra-riscv"
$common = @(
    'run', '--rm',
    '--mount', $mount,
    '--workdir', '/workspace/ultra-riscv/top_tcm_axi/tb',
    $Image
)

$plans = if ($Sweep) {
    @(
        [pscustomobject]@{ Level = 2; Iterations = [int][math]::Round($SmokeIterations * 510.0 / 476.0) },
        [pscustomobject]@{ Level = 3; Iterations = [int][math]::Round($SmokeIterations * 516.0 / 476.0) }
    )
}
else {
    @([pscustomobject]@{ Level = $OptLevel; Iterations = $SmokeIterations })
}

foreach ($plan in $plans) {
    $level = [int]$plan.Level
    $iterations = [int]$plan.Iterations
    & $Builder -RunRoot $RunRoot -ToolchainRoot $ToolchainRoot -OptLevel $level -Iterations $iterations
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $command = @'
set -e
export ENABLE_WAVES=no
test -x build/test.x -a -f build/.ultra_perf_counters_v10 || (make -B build VERILATE_PARAMS="--trace -Wno-fatal -DULTRA_PERF_COUNTERS" && touch build/.ultra_perf_counters_v10)
ELF=/workspace/ultra-riscv/benchmarks/coremark-ultra/build/xpack15.2-opt__OPT_LEVEL__-iter-__SMOKE_ITERATIONS__/coremark.elf
HALT_PC=0x$(riscv64-unknown-elf-nm "$ELF" | grep _halt | cut -c1-8)
TEXT_BYTES=$(riscv64-unknown-elf-size -A "$ELF" | awk '$1==".text" {print $2}')
echo "RUN_CONFIG      : xPack GCC 15.2.0-O__OPT_LEVEL__"
echo "text_bytes      : $TEXT_BYTES"
./build/test.x -f "$ELF" -r "$HALT_PC" -p coremark.signature.bin -j __signature_start -k __signature_end
strings -n 1 coremark.signature.bin
'@
    $command = $command.Replace('__OPT_LEVEL__', [string]$level)
    $command = $command.Replace('__SMOKE_ITERATIONS__', [string]$iterations)
    $output = @(& docker @common -lc $command 2>&1)
    $dockerExitCode = $LASTEXITCODE
    $text = $output -join [Environment]::NewLine
    Write-Output $text
    if ($dockerExitCode -ne 0) { exit $dockerExitCode }

    $ticksMatch = [regex]::Match($text, 'Total ticks\s*:\s*(\d+)')
    $iterationsMatch = [regex]::Match($text, 'Iterations\s*:\s*(\d+)')
    $cycleStartMatch = [regex]::Match($text, 'cycle_start\s*:\s*(\d+)')
    $cycleEndMatch = [regex]::Match($text, 'cycle_end\s*:\s*(\d+)')
    $instretStartMatch = [regex]::Match($text, 'instret_start\s*:\s*(\d+)')
    $instretEndMatch = [regex]::Match($text, 'instret_end\s*:\s*(\d+)')
    $textBytesMatch = [regex]::Match($text, 'text_bytes\s*:\s*(\d+)')
    $perfPatterns = [ordered]@{
        scoreboard      = 'scoreboard_stall_cycles\s*:\s*(\d+)'
        lsu             = 'lsu_stall_cycles\s*:\s*(\d+)'
        pipe            = 'pipe_stall_cycles\s*:\s*(\d+)'
        div             = 'div_wait_cycles\s*:\s*(\d+)'
        csr             = 'csr_wait_cycles\s*:\s*(\d+)'
        branchRequest   = 'branch_request_events\s*:\s*(\d+)'
        branchRedirect  = 'branch_redirect_cycles\s*:\s*(\d+)'
        branchFlush     = 'branch_flush_cycles\s*:\s*(\d+)'
        fetchStarve     = 'fetch_starve_cycles\s*:\s*(\d+)'
    }
    $perfValues = @{}
    foreach ($perfName in $perfPatterns.Keys) {
        $perfMatch = [regex]::Match($text, $perfPatterns[$perfName])
        if (-not $perfMatch.Success) {
            throw "xPack CoreMark output did not contain performance counter: $perfName"
        }
        $perfValues[$perfName] = [decimal]$perfMatch.Groups[1].Value
    }
    if (-not $ticksMatch.Success -or -not $iterationsMatch.Success -or
        -not $cycleStartMatch.Success -or -not $cycleEndMatch.Success -or
        -not $instretStartMatch.Success -or -not $instretEndMatch.Success) {
        throw 'xPack CoreMark output did not contain the required cycle/instret measurements.'
    }

    $totalTicks = [decimal]$ticksMatch.Groups[1].Value
    $iterations = [decimal]$iterationsMatch.Groups[1].Value
    $cycleStart = [decimal]$cycleStartMatch.Groups[1].Value
    $cycleEnd = [decimal]$cycleEndMatch.Groups[1].Value
    $instretStart = [decimal]$instretStartMatch.Groups[1].Value
    $instretEnd = [decimal]$instretEndMatch.Groups[1].Value
    $cycles = $cycleEnd - $cycleStart
    $retired = $instretEnd - $instretStart
    $textBytes = if ($textBytesMatch.Success) { [decimal]$textBytesMatch.Groups[1].Value } else { 0 }
    $frequencyHz = [decimal]$CoremarkFrequencyHz
    $measuredSeconds = $totalTicks / $frequencyHz
    $coremarkPerSecond = $iterations / $measuredSeconds
    $frequencyMHz = $frequencyHz / 1000000
    $coremarkPerMHz = $coremarkPerSecond / $frequencyMHz
    $instructionsPerIteration = $retired / $iterations
    $cyclesPerIteration = $cycles / $iterations
    $cpi = $cycles / $retired
    $scoreboardPerIteration = $perfValues.scoreboard / $iterations
    $lsuPerIteration = $perfValues.lsu / $iterations
    $pipePerIteration = $perfValues.pipe / $iterations
    $divPerIteration = $perfValues.div / $iterations
    $csrPerIteration = $perfValues.csr / $iterations
    $branchRequestPerIteration = $perfValues.branchRequest / $iterations
    $branchRedirectPerIteration = $perfValues.branchRedirect / $iterations
    $branchFlushPerIteration = $perfValues.branchFlush / $iterations
    $fetchStarvePerIteration = $perfValues.fetchStarve / $iterations
    $crcPass = $text -match 'seedcrc\s*: 0xe9f5' -and
        $text -match '\[0\]crclist\s*: 0xe714' -and
        $text -match '\[0\]crcmatrix\s*: 0x1fd7' -and
        $text -match '\[0\]crcstate\s*: 0x8e3a'

    Write-Output ''
    Write-Output 'CoreMark 2-second smoke comparison (non-official score):'
    Write-Output (('  Compiler             : xPack GCC 15.2.0 -O{0}' -f $level))
    Write-Output (('  Clock frequency      : {0:N0} Hz' -f $CoremarkFrequencyHz))
    Write-Output (('  .text bytes          : {0:N0}' -f $textBytes))
    Write-Output (('  Iterations            : {0:N0}' -f $iterations))
    Write-Output (('  Cycle start/end      : {0:N0} / {1:N0}' -f $cycleStart, $cycleEnd))
    Write-Output (('  Instret start/end    : {0:N0} / {1:N0}' -f $instretStart, $instretEnd))
    Write-Output (('  Cycles               : {0:N0}' -f $cycles))
    Write-Output (('  Retired instructions : {0:N0}' -f $retired))
    Write-Output (('  Instructions/iteration: {0:F3}' -f $instructionsPerIteration))
    Write-Output (('  Cycles/iteration     : {0:F3}' -f $cyclesPerIteration))
    Write-Output (('  CPI                  : {0:F6}' -f $cpi))
    Write-Output (('  Scoreboard stalls    : {0:N0} ({1:F3}/iteration)' -f $perfValues.scoreboard, $scoreboardPerIteration))
    Write-Output (('  LSU stalls           : {0:N0} ({1:F3}/iteration)' -f $perfValues.lsu, $lsuPerIteration))
    Write-Output (('  Pipe stalls          : {0:N0} ({1:F3}/iteration)' -f $perfValues.pipe, $pipePerIteration))
    Write-Output (('  DIV wait             : {0:N0} ({1:F3}/iteration)' -f $perfValues.div, $divPerIteration))
    Write-Output (('  CSR wait             : {0:N0} ({1:F3}/iteration)' -f $perfValues.csr, $csrPerIteration))
    Write-Output (('  Branch requests      : {0:N0} ({1:F3}/iteration)' -f $perfValues.branchRequest, $branchRequestPerIteration))
    Write-Output (('  Branch redirects     : {0:N0} ({1:F3}/iteration)' -f $perfValues.branchRedirect, $branchRedirectPerIteration))
    Write-Output (('  Branch flush cycles  : {0:N0} ({1:F3}/iteration)' -f $perfValues.branchFlush, $branchFlushPerIteration))
    Write-Output (('  Fetch starvation     : {0:N0} ({1:F3}/iteration)' -f $perfValues.fetchStarve, $fetchStarvePerIteration))
    Write-Output (('  Measured time         : {0:F6} s' -f $measuredSeconds))
    Write-Output (('  Equivalent CoreMark/s : {0:F3}' -f $coremarkPerSecond))
    Write-Output (('  Equivalent CoreMark/MHz: {0:F6}' -f $coremarkPerMHz))
    Write-Output (('  CRC validation        : {0}' -f ($(if ($crcPass) { 'PASS' } else { 'FAIL' })) ))
    Write-Output '  Note                   : 2-second smoke comparison; not an official 10-second result.'
}
