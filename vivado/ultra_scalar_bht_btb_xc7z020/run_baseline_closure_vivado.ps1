param(
    [ValidateSet('D0', 'D1', 'All')]
    [string]$Config = 'All',
    [switch]$DevFrequency
)

$ErrorActionPreference = 'Stop'
$Vivado = 'E:\Xilinx\Vivado\2022.2\bin\vivado.bat'
$Root = $PSScriptRoot
$Tcl = Join-Path $Root 'implement_param_sweep_ooc.tcl'

if (-not (Test-Path -LiteralPath $Vivado)) {
    throw "Vivado 2022.2 was not found at $Vivado"
}
if (-not (Test-Path -LiteralPath $Tcl)) {
    throw "Implementation Tcl script was not found: $Tcl"
}

$Configs = [ordered]@{
    D0 = @{ ExtraDecode = 1; XilinxRegfile = 1 }
    D1 = @{ ExtraDecode = 1; XilinxRegfile = 1 }
}
$Selected = if ($Config -eq 'All') { @('D0', 'D1') } else { @($Config) }
$ReportSubdir = if ($DevFrequency) { 'baseline_closure/dev_frequency_80MHz' } else { 'baseline_closure/param_sweep' }
$ClockNs = if ($DevFrequency) { '12.500' } else { '10.000' }

foreach ($Name in $Selected) {
    $Spec = $Configs[$Name]
    $Dir = Join-Path $Root ('reports\' + ($ReportSubdir -replace '/', '\') + '\' + $Name)
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    $ConsoleLog = Join-Path $Dir 'vivado_console.log'
    $VivadoLog = Join-Path $Dir 'vivado.log'
    $VivadoJournal = Join-Path $Dir 'vivado.jou'

    Write-Host "=== baseline closure ${Name}: clock=${ClockNs}ns, EXTRA_DECODE_STAGE=$($Spec.ExtraDecode), SUPPORT_REGFILE_XILINX=$($Spec.XilinxRegfile) ==="
    & $Vivado -mode batch -notrace `
        -log $VivadoLog -journal $VivadoJournal `
        -source $Tcl -tclargs $Name $Spec.ExtraDecode $Spec.XilinxRegfile $ClockNs $ReportSubdir *> $ConsoleLog
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -ne 0) {
        throw "Vivado baseline closure $Name failed with exit code $ExitCode. See $ConsoleLog"
    }
    Write-Host "Completed $Name; reports: $Dir"
}
