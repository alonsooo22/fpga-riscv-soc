param(
    [ValidateSet('Project', 'Open', 'Synthesis', 'Implementation')]
    [string]$Action = 'Project'
)

$Vivado = 'E:\Xilinx\Vivado\2022.2\bin\vivado.bat'
$Root = $PSScriptRoot
$Project = Join-Path $Root 'project\ultra_scalar_top_tcm_xc7z020.xpr'

if (-not (Test-Path -LiteralPath $Vivado)) {
    throw "Vivado 2022.2 was not found at $Vivado"
}

switch ($Action) {
    'Project' {
        & $Vivado -mode batch -source (Join-Path $Root 'create_project.tcl')
    }
    'Open' {
        if (-not (Test-Path -LiteralPath $Project)) {
            throw 'Generate the project first with: .\build.ps1 -Action Project'
        }
        & $Vivado $Project
    }
    'Synthesis' {
        & $Vivado -mode batch -source (Join-Path $Root 'synth.tcl')
    }
    'Implementation' {
        & $Vivado -mode batch -source (Join-Path $Root 'implement_ooc.tcl')
    }
}

if ($LASTEXITCODE -ne 0) {
    throw "Vivado exited with code $LASTEXITCODE"
}
