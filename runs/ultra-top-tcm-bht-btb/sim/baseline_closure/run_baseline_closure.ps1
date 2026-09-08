param(
    [ValidateSet('A0', 'A1', 'D0', 'D1', 'All')]
    [string]$Config = 'All',
    [ValidateSet('Unit', 'Frontend', 'Directed', 'IRQ', 'SideEffects', 'CoreMark', 'All')]
    [string]$Test = 'All'
)

$ErrorActionPreference = 'Stop'
$RunRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Image = 'ultra-top-tcm:verilator-5.050-systemc-2.3.1a'
$ReportRoot = Join-Path $RunRoot 'reports\baseline_closure\simulation'
New-Item -ItemType Directory -Path $ReportRoot -Force | Out-Null

$Configs = [ordered]@{
    A0 = @{ ExtraDecode = 0; XilinxRegfile = 0; Predictor = 0 }
    A1 = @{ ExtraDecode = 0; XilinxRegfile = 0; Predictor = 1 }
    D0 = @{ ExtraDecode = 1; XilinxRegfile = 1; Predictor = 0 }
    D1 = @{ ExtraDecode = 1; XilinxRegfile = 1; Predictor = 1 }
}

function Invoke-Container {
    param(
        [string]$Name,
        [string]$Command,
        [hashtable]$Environment = @{}
    )

    $log = Join-Path $ReportRoot ($Name + '.log')
    $dockerArgs = @('--rm', '-v', (('{0}:/work' -f $RunRoot)))
    $dockerArgs += @('-e', 'ENABLE_WAVES=no')
    foreach ($key in $Environment.Keys) {
        $dockerArgs += @('-e', ('{0}={1}' -f $key, $Environment[$key]))
    }
    $dockerArgs += @($Image, '-lc', $Command)

    Write-Host "=== $Name ==="
    & docker run @dockerArgs 2>&1 | Tee-Object -FilePath $log
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$Name failed with exit code $exitCode; see $log"
    }
}

function Invoke-Build {
    param([string]$Name, [hashtable]$Spec)

    $params = "--trace -Wno-fatal -DULTRA_PERF_COUNTERS -GSUPPORT_BRANCH_PREDICTION=$($Spec.Predictor) -GEXTRA_DECODE_STAGE=$($Spec.ExtraDecode) -GSUPPORT_REGFILE_XILINX=$($Spec.XilinxRegfile)"
    $command = "cd /work/top_tcm_axi/tb && " +
        "make -f makefile.generate_verilated clean CORE=riscv && " +
        "make -f makefile.build_verilated clean && " +
        "make -f makefile.build_sysc_tb clean && " +
        "make -C ../../isa_sim lib && " +
        "make -f makefile.generate_verilated CORE=riscv VERILATE_PARAMS='$params' && " +
        "make -f makefile.build_verilated && " +
        "make -f makefile.build_sysc_tb"
        Invoke-Container -Name ($Name + '_build') -Command $command
}

if ($Test -in @('Unit', 'All')) {
    $unitCommand = "cd /work/sim/branch_predictor && rm -rf obj && " +
        "verilator --lint-only --Wno-fatal --top-module riscv_branch_predict -I../../core/riscv ../../core/riscv/riscv_branch_predict.v && " +
        "verilator --binary --timing --Wno-fatal --top-module tb_riscv_branch_predict -I../../core/riscv ../../core/riscv/riscv_branch_predict.v tb_riscv_branch_predict.v -Mdir obj && " +
        "./obj/Vtb_riscv_branch_predict"
    Invoke-Container -Name 'unit_branch_predictor' -Command $unitCommand
}

if ($Test -in @('Frontend', 'All')) {
    $frontendCommand = "cd /work/sim/baseline_closure && rm -rf obj_frontend && " +
        "verilator --binary --timing --Wno-fatal -DULTRA_PERF_COUNTERS --top-module tb_frontend_pressure -I../../core/riscv " +
        "../../core/riscv/riscv_fetch.v ../../core/riscv/riscv_branch_predict.v tb_frontend_pressure.v -Mdir obj_frontend && " +
        "./obj_frontend/Vtb_frontend_pressure"
    Invoke-Container -Name 'frontend_pressure' -Command $frontendCommand
}

$Selected = if ($Config -eq 'All') { @('A0', 'A1', 'D0', 'D1') } else { @($Config) }
$NeedsConfigTest = $Test -in @('Directed', 'IRQ', 'SideEffects', 'CoreMark', 'All')
if ($NeedsConfigTest) {
    foreach ($Name in $Selected) {
        $Spec = $Configs[$Name]
        Invoke-Build -Name $Name -Spec $Spec

        if ($Test -in @('Directed', 'All')) {
            $isaCommand = 'cd /work/top_tcm_axi/tb && ./build/test.x -f /work/sim/branch_predictor/branch_redirect_test.elf -t 0'
            Invoke-Container -Name ($Name + '_isa_smoke') -Command $isaCommand
        }

        if ($Test -in @('IRQ', 'All')) {
            $irqEnv = @{
                ULTRA_IRQ_TEST = 1
                ULTRA_IRQ_MASK_TRIGGER_PC = '0x2024'
                ULTRA_IRQ_MASK_CLEAR_PC = '0x2028'
                ULTRA_IRQ_ENABLED_TRIGGER_PC = '0x2050'
                ULTRA_IRQ_HANDLER_PC = '0x209c'
            }
            $irqCommand = 'cd /work/top_tcm_axi/tb && ./build/test.x -f /work/sim/baseline_closure/irq_test.elf -c 500'
            Invoke-Container -Name ($Name + '_irq') -Environment $irqEnv -Command $irqCommand
        }

        if ($Test -in @('SideEffects', 'All')) {
            $sideEnv = @{
                ULTRA_SIDE_EFFECT_TEST = 1
                ULTRA_SIDE_EXPECT_PRED_TAKEN = $Spec.Predictor
                ULTRA_SIDE_NT_WRONG_PC_0 = '0x2084'
                ULTRA_SIDE_NT_WRONG_PC_1 = '0x20cc'
                ULTRA_SIDE_NT_WRONG_PC_2 = '0x210c'
                ULTRA_SIDE_NT_WRONG_PC_3 = '0x214c'
                ULTRA_SIDE_PT_TARGET_PC_0 = '0x2448'
                ULTRA_SIDE_PT_TARGET_PC_1 = '0x2488'
                ULTRA_SIDE_PT_TARGET_PC_2 = '0x24c8'
                ULTRA_SIDE_PT_TARGET_PC_3 = '0x2508'
            }
            $sideCommand = 'cd /work/top_tcm_axi/tb && ./build/test.x -f /work/sim/baseline_closure/wrong_path_side_effect_test.elf -c 1200'
            Invoke-Container -Name ($Name + '_side_effects') -Environment $sideEnv -Command $sideCommand
        }

        if ($Test -in @('CoreMark', 'All')) {
            $coremarkCommand = 'cd /work/top_tcm_axi/tb && ELF=/work/benchmarks/coremark-ultra/build/xpack15.2-opt3-iter-516/coremark.elf && HALT_PC=0x$(riscv64-unknown-elf-nm $ELF | grep _halt | cut -c1-8) && ./build/test.x -f $ELF -r $HALT_PC -p /work/reports/baseline_closure/simulation/' + $Name + '.signature.bin -j __signature_start -k __signature_end'
            Invoke-Container -Name ($Name + '_coremark_516') -Command $coremarkCommand
        }
    }
}
