[CmdletBinding()]
param(
    [ValidateSet('Prepare', 'BuildShort', 'RunShort', 'BuildFull', 'RunFull', 'Summarize')]
    [string]$Action = 'Prepare',
    [ValidateSet('R', 'A', 'B', 'C', 'All')]
    [string]$Config = 'All',
    [ValidateRange(1, 1000000)]
    [int]$ShortIterations = 16,
    [ValidateRange(1, 1000000)]
    [int]$FullIterations = 516
)

$ErrorActionPreference = 'Stop'

$FollowupRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SimRoot = Join-Path $FollowupRoot 'sim'
$ExperimentRoot = Join-Path $SimRoot 'compiler_screen_20260915'
$SourceRoot = (Resolve-Path 'D:\code\FPGA\runs\ultra-top-tcm-bht-btb\benchmarks\coremark-ultra').Path
$SourceCopy = Join-Path $ExperimentRoot 'source\coremark-ultra'
$ReportDir = Join-Path $FollowupRoot 'reports\compiler_screen_20260915'
$ToolchainRoot = 'D:\code\FPGA\toolchains\xpack-riscv-none-elf-gcc-15.2.0-1'
$Compiler = Join-Path $ToolchainRoot 'bin\riscv-none-elf-gcc.exe'
$SizeTool = Join-Path $ToolchainRoot 'bin\riscv-none-elf-size.exe'
$Objdump = Join-Path $ToolchainRoot 'bin\riscv-none-elf-objdump.exe'
$Readelf = Join-Path $ToolchainRoot 'bin\riscv-none-elf-readelf.exe'
$Nm = Join-Path $ToolchainRoot 'bin\riscv-none-elf-nm.exe'
$UltraHelper = Join-Path $FollowupRoot 'scripts\ultra_dev.ps1'
$Simulator = '/work/early_tcm_e_tcm_v4/top_tcm_axi/tb/build_v4_on/test_v4_on.x'
$RemoteReportDir = '/followup/reports/compiler_screen_20260915'

$Plans = [ordered]@{
    R = [pscustomobject]@{ Name = 'R'; OptLevel = 3; Flags = @('-O3'); Description = 'reference -O3, no LTO' }
    A = [pscustomobject]@{ Name = 'A'; OptLevel = 2; Flags = @('-O2', '-flto'); Description = '-O2 -flto' }
    B = [pscustomobject]@{ Name = 'B'; OptLevel = 3; Flags = @('-O3', '-flto'); Description = '-O3 -flto' }
    C = [pscustomobject]@{ Name = 'C'; OptLevel = 3; Flags = @('-O3', '-flto', '-funroll-loops'); Description = '-O3 -flto -funroll-loops' }
}

$SourceFiles = @(
    'core_main.c', 'core_list_join.c', 'core_matrix.c', 'core_state.c',
    'core_util.c', 'core_portme.c', 'ee_printf.c', 'coremark.h',
    'core_portme.h', 'startup.S', 'linker.ld', 'Makefile'
)

function Assert-Inputs {
    foreach ($path in @($SourceRoot, $ToolchainRoot, $Compiler, $SizeTool, $Objdump,
                        $Readelf, $Nm, $UltraHelper)) {
        if (-not (Test-Path -LiteralPath $path)) { throw "Compiler screening input is missing: $path" }
    }
    $simulatorHost = Join-Path $SimRoot 'early_tcm_e_tcm_v4\top_tcm_axi\tb\build_v4_on\test_v4_on.x'
    if (-not (Test-Path -LiteralPath $simulatorHost)) { throw "Existing v4 simulator is missing: $simulatorHost" }
}

function Ensure-Directories {
    New-Item -ItemType Directory -Path $ExperimentRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

function Ensure-SourceCopy {
    Ensure-Directories
    $missing = $false
    foreach ($name in $SourceFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $SourceCopy $name))) { $missing = $true; break }
    }
    if ($missing) {
        New-Item -ItemType Directory -Path $SourceCopy -Force | Out-Null
        foreach ($name in $SourceFiles) {
            $input = Join-Path $SourceRoot $name
            if (-not (Test-Path -LiteralPath $input)) { throw "CoreMark source file is missing: $input" }
            Copy-Item -LiteralPath $input -Destination (Join-Path $SourceCopy $name) -Force
        }
        @(
            'Source copy for compiler screening',
            "origin=$SourceRoot",
            "destination=$SourceCopy",
            'algorithm sources are copied without edits',
            ("files={0}" -f ($SourceFiles -join ','))
        ) | Set-Content -LiteralPath (Join-Path $ExperimentRoot 'source_copy.txt') -Encoding UTF8
    }
}

function Get-SelectedConfigs {
    if ($Config -eq 'All') { return @('R', 'B', 'A', 'C') }
    return @($Config)
}

function Get-CommonFlags([int]$Iterations, [int]$OptLevel) {
    return @(
        '-march=rv32im_zicsr', '-mabi=ilp32', '-mcmodel=medany', '-msmall-data-limit=0',
        '-ffreestanding', '-fno-builtin', '-fno-stack-protector', '-fno-pic',
        '-fdata-sections', '-ffunction-sections', '-std=gnu11', '-Wall', '-Wextra',
        "-I$SourceCopy", '-DTOTAL_DATA_SIZE=2000', '-DMEM_METHOD=MEM_STATIC',
        '-DMULTITHREAD=1', "-DITERATIONS=$Iterations", '-DHAS_FLOAT=0',
        '-DHAS_STDIO=0', '-DHAS_PRINTF=0', '-DMAIN_HAS_NOARGC=1',
        '-DMAIN_HAS_NORETURN=0', '-DSEED_METHOD=SEED_VOLATILE', '-DMEM_LOCATION="TCM"',
        "-DULTRA_OPT_LEVEL=$OptLevel", '-DULTRA_PERF_COUNTERS', '-DULTRA_XPACK_GCC'
    )
}

function Add-BuildLog([string]$Path, [string]$Text) {
    Add-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Invoke-Tool([string]$Tool, [string[]]$Arguments, [string]$LogPath) {
    Add-BuildLog $LogPath ("COMMAND: {0} {1}" -f $Tool, ($Arguments -join ' '))
    $output = @(& $Tool @Arguments 2>&1)
    $rc = $LASTEXITCODE
    if ($output.Count -gt 0) { $output | Add-Content -LiteralPath $LogPath -Encoding UTF8 }
    if ($rc -ne 0) { throw "Tool failed with exit $($rc): $Tool" }
}

function Build-One([string]$Name, [string]$Kind, [int]$Iterations) {
    Ensure-SourceCopy
    $plan = $Plans[$Name]
    $outDir = Join-Path $ExperimentRoot ("build\{0}\{1}" -f $Kind, $Name)
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $log = Join-Path $outDir 'build.log'
    @(
        "CONFIG=$Name", "WORKLOAD=$Kind", "ITERATIONS=$Iterations",
        "COMPILER=$Compiler", "TOOLCHAIN=$ToolchainRoot", "DESCRIPTION=$($plan.Description)",
        ('FLAGS=-march=rv32im_zicsr -mabi=ilp32 -mcmodel=medany -msmall-data-limit=0 ' +
         ($plan.Flags -join ' ') + ' -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fdata-sections -ffunction-sections'),
        ('LTO_AT_COMPILE_AND_LINK=' + $(if ($plan.Flags -contains '-flto') { 'yes' } else { 'no' }))
    ) | Set-Content -LiteralPath $log -Encoding UTF8

    $common = Get-CommonFlags $Iterations $plan.OptLevel
    $sources = @('core_main.c', 'core_list_join.c', 'core_matrix.c', 'core_state.c',
                 'core_util.c', 'core_portme.c', 'ee_printf.c', 'startup.S')
    $objects = @()
    foreach ($source in $sources) {
        $input = Join-Path $SourceCopy $source
        $object = Join-Path $outDir (([IO.Path]::GetFileNameWithoutExtension($source)) + '.o')
        $args = @($common + $plan.Flags + @('-c', $input, '-o', $object))
        Invoke-Tool $Compiler $args $log
        $objects += $object
    }

    $elf = Join-Path $outDir 'coremark.elf'
    $map = Join-Path $outDir 'coremark.map'
    $dis = Join-Path $outDir 'coremark.dis'
    $linker = Join-Path $SourceCopy 'linker.ld'
    $linkFlags = @('-nostdlib', '-Wl,--gc-sections', "-Wl,-T,$linker", "-Wl,-Map,$map")
    Invoke-Tool $Compiler @($common + $plan.Flags + $linkFlags + $objects + @('-lgcc', '-o', $elf)) $log

    $sectionPath = Join-Path $outDir 'sections.txt'
    Invoke-Tool $SizeTool @('-A', $elf) $sectionPath
    Invoke-Tool $Readelf @('-S', $elf) (Join-Path $outDir 'readelf_sections.txt')
    $disOutput = @(& $Objdump '-d' '-S' $elf 2>&1)
    $disRc = $LASTEXITCODE
    $disOutput | Set-Content -LiteralPath $dis -Encoding UTF8
    if ($disRc -ne 0) { throw "objdump failed for $elf with exit $disRc" }
    $nmOutput = @(& $Nm $elf 2>&1)
    $nmRc = $LASTEXITCODE
    $nmOutput | Set-Content -LiteralPath (Join-Path $outDir 'symbols.txt') -Encoding UTF8
    if ($nmRc -ne 0) { throw "nm failed for $elf with exit $nmRc" }

    $manifestPath = Join-Path $ExperimentRoot 'build_manifest.csv'
    $row = [pscustomobject]@{
        config = $Name; workload = $Kind; iterations = $Iterations
        compiler = $Compiler; compiler_version = 'xPack GNU RISC-V Embedded GCC 15.2.0'
        flags = $plan.Flags -join ' '; lto_compile_and_link = if ($plan.Flags -contains '-flto') { 'yes' } else { 'no' }
        elf = $elf; map = $map; disassembly = $dis; build_log = $log
    }
    $existing = if (Test-Path -LiteralPath $manifestPath) { @(Import-Csv -LiteralPath $manifestPath) } else { @() }
    $existing = @($existing | Where-Object { -not ($_.config -eq $Name -and $_.workload -eq $Kind) })
    @($existing + $row) | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8
    Write-Output "BUILT config=$Name workload=$Kind elf=$elf"
}

function Get-ContainerPath([string]$HostPath) {
    $relative = $HostPath.Substring($SimRoot.Length).TrimStart('\').Replace('\', '/')
    return "/work/$relative"
}

function Run-One([string]$Name, [string]$Kind, [int]$Iterations) {
    Ensure-SourceCopy
    $elfHost = Join-Path $ExperimentRoot ("build\{0}\{1}\coremark.elf" -f $Kind, $Name)
    if (-not (Test-Path -LiteralPath $elfHost)) { throw "ELF not found; build first: $elfHost" }
    Ensure-Directories
    $elf = Get-ContainerPath $elfHost
    $logName = "{0}_{1}.log" -f $Kind, $Name
    $sigName = "{0}_{1}.signature.bin" -f $Kind, $Name
    $sigTextName = "{0}_{1}.signature.txt" -f $Kind, $Name
    $remoteLog = "$RemoteReportDir/$logName"
    $remoteSig = "$RemoteReportDir/$sigName"
    $remoteSigText = "$RemoteReportDir/$sigTextName"
    $cycleLimit = if ($Kind -eq 'short') { 15000000 } else { 250000000 }
    $timeout = if ($Kind -eq 'short') { '120s' } else { '900s' }
    $description = $Plans[$Name].Description
    $flagText = $Plans[$Name].Flags -join ' '
    $cmd = @'
set -e
cd /work/early_tcm_e_tcm_v4/top_tcm_axi/tb
ELF=__ELF__
LOG=__LOG__
SIG=__SIG__
SIGTXT=__SIGTXT__
HALT_PC=0x$(riscv64-unknown-elf-nm "$ELF" | awk '$3=="_halt"{print $1; exit}')
test -n "$HALT_PC"
rm -f "$LOG" "$SIG" "$SIGTXT" verilator.vcd sysc_wave.vcd
{
  echo "RUN_CONFIG=__NAME__"
  echo "WORKLOAD=__KIND__"
  echo "ITERATIONS=__ITERATIONS__"
  echo "COMPILER=xPack GNU RISC-V Embedded GCC 15.2.0"
  echo "FLAGS=__FLAGS__"
  echo "ELF=$ELF"
  echo "HALT_PC=$HALT_PC"
} > "$LOG"
set +e
env -u ULTRA_V4_CORRECTED_OBS -u ULTRA_V4_SHARED_OBS -u ULTRA_EARLY_TCM_TRACE ENABLE_WAVES=no /usr/bin/timeout --foreground __TIMEOUT__ __SIMULATOR__ -f "$ELF" -r "$HALT_PC" -p "$SIG" -j __signature_start -k __signature_end -c __CYCLE_LIMIT__ >> "$LOG" 2>&1
rc=$?
set -e
printf 'SIM_COMMAND_EXIT=%s\n' "$rc" >> "$LOG"
if test -s "$SIG"; then strings -n 1 "$SIG" > "$SIGTXT"; cat "$SIGTXT" >> "$LOG"; fi
cat "$LOG"
test "$rc" -eq 0
test -s "$SIG"
test ! -e verilator.vcd
test ! -e sysc_wave.vcd
test ! -e /followup/reports/compiler_screen_20260915/verilator.vcd
test ! -e /followup/reports/compiler_screen_20260915/sysc_wave.vcd
'@
    $cmd = $cmd.Replace('__ELF__', $elf).Replace('__LOG__', $remoteLog)
    $cmd = $cmd.Replace('__SIG__', $remoteSig).Replace('__SIGTXT__', $remoteSigText)
    $cmd = $cmd.Replace('__NAME__', $Name).Replace('__KIND__', $Kind)
    $cmd = $cmd.Replace('__ITERATIONS__', [string]$Iterations).Replace('__FLAGS__', $flagText)
    $cmd = $cmd.Replace('__TIMEOUT__', $timeout).Replace('__SIMULATOR__', $Simulator)
    $cmd = $cmd.Replace('__CYCLE_LIMIT__', [string]$cycleLimit)
    & $UltraHelper -Action Exec -Command $cmd
    if ($LASTEXITCODE -ne 0) { throw "Simulation failed for $Name/$Kind" }
    Write-Output "RAN config=$Name workload=$Kind log=$ReportDir\$logName"
}

function Get-LogNumber([string]$Text, [string]$Pattern) {
    $match = [regex]::Match($Text, $Pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) { return [long]$match.Groups[1].Value }
    return $null
}

function Get-Section([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ Size = $null; Address = $null } }
    $text = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($text, "(?m)^\.$Name\s+(\d+)\s+(\d+)")
    if ($match.Success) {
        return [pscustomobject]@{ Size = [long]$match.Groups[1].Value; Address = [long]$match.Groups[2].Value }
    }
    return [pscustomobject]@{ Size = $null; Address = $null }
}

function Summarize-One([string]$Name, [string]$Kind, [int]$Iterations) {
    $outDir = Join-Path $ExperimentRoot ("build\{0}\{1}" -f $Kind, $Name)
    $logPath = Join-Path $ReportDir ("{0}_{1}.log" -f $Kind, $Name)
    if (-not (Test-Path -LiteralPath $logPath)) {
        return [pscustomobject]@{ Config = $Name; Workload = $Kind; Status = 'NOT_RUN' }
    }
    $text = Get-Content -LiteralPath $logPath -Raw
    $cycleStart = Get-LogNumber $text '(?m)^\s*cycle_start\s*:\s*(\d+)'
    $cycleEnd = Get-LogNumber $text '(?m)^\s*cycle_end\s*:\s*(\d+)'
    $instretStart = Get-LogNumber $text '(?m)^\s*instret_start\s*:\s*(\d+)'
    $instretEnd = Get-LogNumber $text '(?m)^\s*instret_end\s*:\s*(\d+)'
    $runIterations = Get-LogNumber $text '(?m)^\s*Iterations\s*:\s*(\d+)'
    if ($null -eq $runIterations) { $runIterations = $Iterations }
    $cycles = if ($null -ne $cycleStart -and $null -ne $cycleEnd) { $cycleEnd - $cycleStart } else { $null }
    $retired = if ($null -ne $instretStart -and $null -ne $instretEnd) { $instretEnd - $instretStart } else { $null }
    $expectedFinalCrc = if ($Kind -eq 'short') { 'dd50' } else { 'e6dc' }
    $crc = ($text -match '(?im)^\s*seedcrc\s*:\s*0xe9f5') -and
           ($text -match '(?im)^\s*\[0\]crclist\s*:\s*0xe714') -and
           ($text -match '(?im)^\s*\[0\]crcmatrix\s*:\s*0x1fd7') -and
           ($text -match '(?im)^\s*\[0\]crcstate\s*:\s*0x8e3a') -and
           ($text -match ("(?im)^\s*(?:\[0\])?crcfinal\s*:\s*0x{0}" -f $expectedFinalCrc))
    $commandExit = Get-LogNumber $text '(?m)^SIM_COMMAND_EXIT=(\d+)'
    $status = if ($commandExit -eq 0 -and $crc -and $null -ne $cycles -and $cycles -gt 0) { 'PASS' } else { 'FAIL' }
    $textSection = Get-Section (Join-Path $outDir 'sections.txt') 'text'
    $rodataSection = Get-Section (Join-Path $outDir 'sections.txt') 'rodata'
    $dataSection = Get-Section (Join-Path $outDir 'sections.txt') 'data'
    $bssSection = Get-Section (Join-Path $outDir 'sections.txt') 'bss'
    $signatureSection = Get-Section (Join-Path $outDir 'sections.txt') 'signature'
    $perfPatterns = [ordered]@{
        Scoreboard = 'scoreboard_stall_cycles'
        Lsu = 'lsu_stall_cycles'
        Pipe = 'pipe_stall_cycles'
        Div = 'div_wait_cycles'
        Csr = 'csr_wait_cycles'
        BranchRequest = 'branch_request_events'
        BranchRedirect = 'branch_redirect_cycles'
        BranchFlush = 'branch_flush_cycles'
        FetchStarve = 'fetch_starve_cycles'
    }
    $row = [ordered]@{
        Config = $Name; Workload = $Kind; Status = $status; CRC = if ($crc) { 'PASS' } else { 'FAIL' }
        Iterations = $runIterations; Cycles = $cycles
        CyclesPerIteration = if ($null -ne $cycles -and $runIterations) { [double]$cycles / $runIterations } else { $null }
        Retired = $retired
        RetiredPerIteration = if ($null -ne $retired -and $runIterations) { [double]$retired / $runIterations } else { $null }
        CPI = if ($null -ne $cycles -and $null -ne $retired -and $retired -gt 0) { [double]$cycles / $retired } else { $null }
        CoreMarkPerMHz = if ($null -ne $cycles -and $cycles -gt 0) { [double]$runIterations * 1000000.0 / $cycles } else { $null }
        TextBytes = $textSection.Size; TextAddress = $textSection.Address
        RodataBytes = $rodataSection.Size; RodataAddress = $rodataSection.Address
        DataBytes = $dataSection.Size; DataAddress = $dataSection.Address
        BssBytes = $bssSection.Size; BssAddress = $bssSection.Address
        SignatureBytes = $signatureSection.Size; SignatureAddress = $signatureSection.Address
        CommandExit = $commandExit; Log = $logPath
        ELF = Join-Path $outDir 'coremark.elf'; Map = Join-Path $outDir 'coremark.map'
        Disassembly = Join-Path $outDir 'coremark.dis'
    }
    foreach ($label in $perfPatterns.Keys) {
        $row[$label] = Get-LogNumber $text ("(?m)^\s*{0}\s*:\s*(\d+)" -f [regex]::Escape($perfPatterns[$label]))
    }
    return [pscustomobject]$row
}

function Summarize-All {
    Ensure-Directories
    $rows = @()
    foreach ($kind in @('short', 'full')) {
        foreach ($name in @('R', 'A', 'B', 'C')) {
            $iterations = if ($kind -eq 'short') { $ShortIterations } else { $FullIterations }
            $rows += Summarize-One $name $kind $iterations
        }
    }
    $csv = Join-Path $ReportDir 'compiler_screen_results.csv'
    $rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    $rows | Format-Table Config,Workload,Status,Iterations,Cycles,Retired,CPI,CoreMarkPerMHz,TextBytes,CRC
    Write-Output "RESULT_CSV=$csv"
}

Assert-Inputs
switch ($Action) {
    'Prepare' {
        Ensure-SourceCopy
        Write-Output "PREPARED=$ExperimentRoot"
        Write-Output "SOURCE_COPY=$SourceCopy"
        Write-Output "TOOLCHAIN=$ToolchainRoot"
    }
    'BuildShort' {
        Ensure-SourceCopy
        foreach ($name in (Get-SelectedConfigs)) { Build-One $name 'short' $ShortIterations }
    }
    'RunShort' {
        foreach ($name in (Get-SelectedConfigs)) { Run-One $name 'short' $ShortIterations }
    }
    'BuildFull' {
        Ensure-SourceCopy
        foreach ($name in (Get-SelectedConfigs)) { Build-One $name 'full' $FullIterations }
    }
    'RunFull' {
        foreach ($name in (Get-SelectedConfigs)) { Run-One $name 'full' $FullIterations }
    }
    'Summarize' {
        Summarize-All
    }
}
