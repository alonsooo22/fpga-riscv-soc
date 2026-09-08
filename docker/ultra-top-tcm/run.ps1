param(
    [ValidateSet('build-image', 'build', 'run', 'coremark-build', 'coremark-quick', 'coremark-smoke', 'coremark-sweep', 'coremark-xpack-sweep', 'coremark-full', 'shell', 'clean')]
    [string]$Action = 'shell',
    [ValidateRange(1, 1000000)]
    [int]$SmokeIterations = 476,
    [ValidateSet(2, 3)]
    [int]$OptLevel = 2,
    [ValidateRange(1, 10000000000)]
    [long]$CoremarkFrequencyHz = 100000000,
    [string]$XpackRoot = 'D:\code\FPGA\toolchains\xpack-riscv-none-elf-gcc-15.2.0-1'
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$BaselineRoot = Join-Path $ProjectRoot 'baseline\ultraembedded-riscv'
$RunRoot = Join-Path $ProjectRoot 'runs\ultra-top-tcm'
$CoremarkSource = Join-Path $ProjectRoot 'benchmarks\coremark-ultra'
$CompatTestbench = Join-Path $PSScriptRoot 'compat\testbench.h'
$CompatRtlRoot = Join-Path $PSScriptRoot 'compat\rtl'
$Image = 'ultra-top-tcm:verilator-5.050-systemc-2.3.1a'
$DockerContext = $PSScriptRoot

if (-not (Test-Path -LiteralPath $BaselineRoot)) {
    throw "Ultra scalar baseline not found: $BaselineRoot"
}
if (-not (Test-Path -LiteralPath $CompatTestbench)) {
    throw "Compatibility testbench overlay not found: $CompatTestbench"
}
if (-not (Test-Path -LiteralPath $CoremarkSource)) {
    throw "Ultra CoreMark port not found: $CoremarkSource"
}
if (-not (Test-Path -LiteralPath $CompatRtlRoot)) {
    throw "Performance-counter RTL overlay not found: $CompatRtlRoot"
}

if ($Action -eq 'build-image') {
    & docker build --tag $Image $DockerContext
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    exit 0
}

if (-not (Test-Path -LiteralPath $RunRoot)) {
    New-Item -ItemType Directory -Path $RunRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $BaselineRoot '*') -Destination $RunRoot -Recurse -Force
}

$RunCoremark = Join-Path $RunRoot 'benchmarks\coremark-ultra'
New-Item -ItemType Directory -Path $RunCoremark -Force | Out-Null
Copy-Item -Path (Join-Path $CoremarkSource '*') -Destination $RunCoremark -Recurse -Force

# Keep the upstream baseline untouched; apply only this Verilator/SystemC
# compatibility overlay to the isolated disposable run copy.
$RunTestbench = Join-Path $RunRoot 'top_tcm_axi\tb\testbench.h'
Copy-Item -LiteralPath $CompatTestbench -Destination $RunTestbench -Force
$RunMain = Join-Path $RunRoot 'top_tcm_axi\tb\main.cpp'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'compat\main.cpp') -Destination $RunMain -Force
$RunSyscMakefile = Join-Path $RunRoot 'top_tcm_axi\tb\makefile.build_sysc_tb'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'compat\makefile.build_sysc_tb') -Destination $RunSyscMakefile -Force
$RunVerilatedMakefile = Join-Path $RunRoot 'top_tcm_axi\tb\makefile.build_verilated'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'compat\makefile.build_verilated') -Destination $RunVerilatedMakefile -Force

# The performance counter is an experiment-only RTL overlay. Copy only the
# listed overlay files into the isolated run tree; never modify the baseline.
Get-ChildItem -LiteralPath $CompatRtlRoot -File -Recurse | ForEach-Object {
    $relative = $_.FullName.Substring($CompatRtlRoot.Length).TrimStart('\\')
    $destination = Join-Path $RunRoot $relative
    $destinationDir = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
}

$mount = "type=bind,source=$RunRoot,target=/workspace/ultra-riscv"
$common = @(
    'run', '--rm',
    '--mount', $mount,
    '--workdir', '/workspace/ultra-riscv/top_tcm_axi/tb',
    $Image
)

switch ($Action) {
    'build' {
        & docker @common -lc "make -B build VERILATE_PARAMS='--trace -Wno-fatal'"
    }
    'run' {
        & docker @common -lc "make -B run VERILATE_PARAMS='--trace -Wno-fatal'"
    }
    'coremark-build' {
        & docker @common -lc "make -C /workspace/ultra-riscv/benchmarks/coremark-ultra -B ITERATIONS=16 OPT_LEVEL=$OptLevel CONFIG=opt$OptLevel all"
    }
    'coremark-quick' {
        $quickCommand = @'
set -e
export ENABLE_WAVES=no
test -x build/test.x -a -f build/.ultra_perf_counters_v10 || (make -B build VERILATE_PARAMS="--trace -Wno-fatal -DULTRA_PERF_COUNTERS" && touch build/.ultra_perf_counters_v10)
make -C /workspace/ultra-riscv/benchmarks/coremark-ultra -B ITERATIONS=1 OPT_LEVEL=__OPT_LEVEL__ CONFIG=opt__OPT_LEVEL__ all
ELF=/workspace/ultra-riscv/benchmarks/coremark-ultra/build/opt__OPT_LEVEL__-iter-1/coremark.elf
HALT_PC=0x$(riscv64-unknown-elf-nm "$ELF" | grep _halt | cut -c1-8)
./build/test.x -f "$ELF" -r "$HALT_PC" -p coremark.signature.bin -j __signature_start -k __signature_end
strings -n 1 coremark.signature.bin
'@
        $quickCommand = $quickCommand.Replace('__OPT_LEVEL__', [string]$OptLevel)
        & docker @common -lc $quickCommand
    }
    'coremark-smoke' {
        $smokeCommand = @'
set -e
export ENABLE_WAVES=no
test -x build/test.x -a -f build/.ultra_perf_counters_v10 || (make -B build VERILATE_PARAMS="--trace -Wno-fatal -DULTRA_PERF_COUNTERS" && touch build/.ultra_perf_counters_v10)
make -C /workspace/ultra-riscv/benchmarks/coremark-ultra -B ITERATIONS=__SMOKE_ITERATIONS__ OPT_LEVEL=__OPT_LEVEL__ CONFIG=opt__OPT_LEVEL__ all
ELF=/workspace/ultra-riscv/benchmarks/coremark-ultra/build/opt__OPT_LEVEL__-iter-__SMOKE_ITERATIONS__/coremark.elf
HALT_PC=0x$(riscv64-unknown-elf-nm "$ELF" | grep _halt | cut -c1-8)
TEXT_BYTES=$(riscv64-unknown-elf-size -A "$ELF" | awk '$1==".text" {print $2}')
echo "RUN_CONFIG      : GCC13.2-O__OPT_LEVEL__"
echo "text_bytes      : $TEXT_BYTES"
./build/test.x -f "$ELF" -r "$HALT_PC" -p coremark.signature.bin -j __signature_start -k __signature_end
strings -n 1 coremark.signature.bin
'@
        $smokeCommand = $smokeCommand.Replace('__SMOKE_ITERATIONS__', [string]$SmokeIterations)
        $smokeCommand = $smokeCommand.Replace('__OPT_LEVEL__', [string]$OptLevel)
        $smokeOutput = @(& docker @common -lc $smokeCommand 2>&1)
        $dockerExitCode = $LASTEXITCODE
        $smokeText = $smokeOutput -join [Environment]::NewLine
        Write-Output $smokeText
        if ($dockerExitCode -ne 0) { exit $dockerExitCode }

        $ticksMatch = [regex]::Match($smokeText, 'Total ticks\s*:\s*(\d+)')
        $iterationsMatch = [regex]::Match($smokeText, 'Iterations\s*:\s*(\d+)')
        $cycleStartMatch = [regex]::Match($smokeText, 'cycle_start\s*:\s*(\d+)')
        $cycleEndMatch = [regex]::Match($smokeText, 'cycle_end\s*:\s*(\d+)')
        $instretStartMatch = [regex]::Match($smokeText, 'instret_start\s*:\s*(\d+)')
        $instretEndMatch = [regex]::Match($smokeText, 'instret_end\s*:\s*(\d+)')
        $textBytesMatch = [regex]::Match($smokeText, 'text_bytes\s*:\s*(\d+)')
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
            $perfMatch = [regex]::Match($smokeText, $perfPatterns[$perfName])
            if (-not $perfMatch.Success) {
                throw "CoreMark smoke output did not contain performance counter: $perfName"
            }
            $perfValues[$perfName] = [decimal]$perfMatch.Groups[1].Value
        }
        if (-not $ticksMatch.Success -or -not $iterationsMatch.Success -or
            -not $cycleStartMatch.Success -or -not $cycleEndMatch.Success -or
            -not $instretStartMatch.Success -or -not $instretEndMatch.Success) {
            throw 'CoreMark smoke output did not contain the required cycle/instret measurements.'
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
        $crcPass = $smokeText -match 'seedcrc\s*: 0xe9f5' -and
            $smokeText -match '\[0\]crclist\s*: 0xe714' -and
            $smokeText -match '\[0\]crcmatrix\s*: 0x1fd7' -and
            $smokeText -match '\[0\]crcstate\s*: 0x8e3a'

        Write-Output ''
        Write-Output 'CoreMark 2-second smoke comparison (non-official score):'
        Write-Output (('  Compiler             : GCC 13.2 -O{0}' -f $OptLevel))
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
        Write-Output (('  CRC validation        : {0}' -f ($(if ($crcPass) { 'PASS' } else { 'FAIL' }))))
        Write-Output '  Note                   : 2-second smoke comparison; not an official 10-second result.'
    }
    'coremark-sweep' {
        foreach ($level in @(2, 3)) {
            $levelIterations = if ($level -eq 3) {
                [int][math]::Round($SmokeIterations * 512.0 / 476.0)
            }
            else {
                $SmokeIterations
            }
            & $PSCommandPath -Action coremark-smoke -SmokeIterations $levelIterations -OptLevel $level -CoremarkFrequencyHz $CoremarkFrequencyHz
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
    }
    'coremark-xpack-sweep' {
        & (Join-Path $PSScriptRoot 'run-coremark-xpack.ps1') -RunRoot $RunRoot -ToolchainRoot $XpackRoot -SmokeIterations $SmokeIterations -CoremarkFrequencyHz $CoremarkFrequencyHz -Image $Image -Sweep
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    'coremark-full' {
        $fullCommand = @'
set -e
export ENABLE_WAVES=no
test -x build/test.x -a -f build/.ultra_perf_counters_v10 || (make -B build VERILATE_PARAMS="--trace -Wno-fatal -DULTRA_PERF_COUNTERS" && touch build/.ultra_perf_counters_v10)
make -C /workspace/ultra-riscv/benchmarks/coremark-ultra -B ITERATIONS=18000 OPT_LEVEL=__OPT_LEVEL__ CONFIG=opt__OPT_LEVEL__ all
ELF=/workspace/ultra-riscv/benchmarks/coremark-ultra/build/opt__OPT_LEVEL__-iter-18000/coremark.elf
HALT_PC=0x$(riscv64-unknown-elf-nm "$ELF" | grep _halt | cut -c1-8)
./build/test.x -f "$ELF" -r "$HALT_PC" -p coremark.signature.bin -j __signature_start -k __signature_end
strings -n 1 coremark.signature.bin
'@
        $fullCommand = $fullCommand.Replace('__OPT_LEVEL__', [string]$OptLevel)
        & docker @common -lc $fullCommand
    }
    'clean' {
        & docker @common -lc 'make clean'
    }
    'shell' {
        & docker @common -it
    }
}

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
