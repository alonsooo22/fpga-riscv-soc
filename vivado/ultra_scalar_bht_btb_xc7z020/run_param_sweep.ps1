param(
    [ValidateSet('A0', 'A1', 'D0', 'D1', 'All')]
    [string]$Config = 'All'
)

$ErrorActionPreference = 'Stop'
$Vivado = 'E:\Xilinx\Vivado\2022.2\bin\vivado.bat'
$Root = $PSScriptRoot
$Tcl = Join-Path $Root 'implement_param_sweep_ooc.tcl'
$ReportRoot = Join-Path $Root 'reports\param_sweep'

if (-not (Test-Path -LiteralPath $Vivado)) {
    throw "Vivado 2022.2 was not found at $Vivado"
}
if (-not (Test-Path -LiteralPath $Tcl)) {
    throw "Parameter sweep Tcl script was not found: $Tcl"
}

$Configs = [ordered]@{
    A0 = @{ ExtraDecode = 0; XilinxRegfile = 0; Predictor = 0 }
    A1 = @{ ExtraDecode = 0; XilinxRegfile = 0; Predictor = 1 }
    D0 = @{ ExtraDecode = 1; XilinxRegfile = 1; Predictor = 0 }
    D1 = @{ ExtraDecode = 1; XilinxRegfile = 1; Predictor = 1 }
}
$Selected = if ($Config -eq 'All') { @('A0', 'A1', 'D0', 'D1') } else { @($Config) }

New-Item -ItemType Directory -Path $ReportRoot -Force | Out-Null
foreach ($Name in $Selected) {
    $Spec = $Configs[$Name]
    $Dir = Join-Path $ReportRoot $Name
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    $ConsoleLog = Join-Path $Dir 'vivado_console.log'
    $VivadoLog = Join-Path $Dir 'vivado.log'
    $VivadoJournal = Join-Path $Dir 'vivado.jou'

    Write-Host "=== Vivado parameter sweep ${Name}: EXTRA_DECODE_STAGE=$($Spec.ExtraDecode), SUPPORT_REGFILE_XILINX=$($Spec.XilinxRegfile), SUPPORT_BRANCH_PREDICTION=$($Spec.Predictor) ==="
    & $Vivado -mode batch -notrace `
        -log $VivadoLog -journal $VivadoJournal `
        -source $Tcl -tclargs $Name $Spec.ExtraDecode $Spec.XilinxRegfile *> $ConsoleLog
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -ne 0) {
        throw "Vivado parameter sweep $Name failed with exit code $ExitCode. See $ConsoleLog"
    }
    Write-Host "Completed $Name; reports: $Dir"
}
