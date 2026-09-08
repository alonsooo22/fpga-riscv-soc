param(
    [Parameter(Mandatory = $true)]
    [string]$RunRoot,
    [Parameter(Mandatory = $true)]
    [string]$ToolchainRoot,
    [ValidateSet(2, 3)]
    [int]$OptLevel = 2,
    [ValidateRange(1, 1000000)]
    [int]$Iterations = 476
)

$ErrorActionPreference = 'Stop'

$SourceRoot = Join-Path $RunRoot 'benchmarks\coremark-ultra'
$OutputRoot = Join-Path $SourceRoot ('build\xpack15.2-opt{0}-iter-{1}' -f $OptLevel, $Iterations)
$Compiler = Join-Path $ToolchainRoot 'bin\riscv-none-elf-gcc.exe'
$Size = Join-Path $ToolchainRoot 'bin\riscv-none-elf-size.exe'
$Objdump = Join-Path $ToolchainRoot 'bin\riscv-none-elf-objdump.exe'
$Linker = Join-Path $SourceRoot 'linker.ld'

foreach ($path in @($SourceRoot, $Compiler, $Size, $Objdump, $Linker)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "xPack CoreMark input not found: $path"
    }
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$common = @(
    '-march=rv32im_zicsr',
    '-mabi=ilp32',
    '-mcmodel=medany',
    '-msmall-data-limit=0',
    "-O$OptLevel",
    '-ffreestanding',
    '-fno-builtin',
    '-fno-stack-protector',
    '-fno-pic',
    '-fdata-sections',
    '-ffunction-sections',
    '-std=gnu11',
    '-Wall',
    '-Wextra',
    "-I$SourceRoot"
)
$defines = @(
    '-DTOTAL_DATA_SIZE=2000',
    '-DMEM_METHOD=MEM_STATIC',
    '-DMULTITHREAD=1',
    "-DITERATIONS=$Iterations",
    '-DHAS_FLOAT=0',
    '-DHAS_STDIO=0',
    '-DHAS_PRINTF=0',
    '-DMAIN_HAS_NOARGC=1',
    '-DMAIN_HAS_NORETURN=0',
    '-DSEED_METHOD=SEED_VOLATILE',
    '-DMEM_LOCATION="TCM"',
    "-DULTRA_OPT_LEVEL=$OptLevel",
    '-DULTRA_PERF_COUNTERS',
    '-DULTRA_XPACK_GCC'
)

$sources = @(
    'core_main.c',
    'core_list_join.c',
    'core_matrix.c',
    'core_state.c',
    'core_util.c',
    'core_portme.c',
    'ee_printf.c',
    'startup.S'
)
$objects = @()
foreach ($source in $sources) {
    $input = Join-Path $SourceRoot $source
    $object = Join-Path $OutputRoot ([IO.Path]::GetFileNameWithoutExtension($source) + '.o')
    & $Compiler @defines @common '-c' $input '-o' $object
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $objects += $object
}

$elf = Join-Path $OutputRoot 'coremark.elf'
$map = Join-Path $OutputRoot 'coremark.map'
$disassembly = Join-Path $OutputRoot 'coremark.dis'
$linkFlags = @(
    '-nostdlib',
    '-Wl,--gc-sections',
    "-Wl,-T,$Linker",
    "-Wl,-Map,$map"
)
& $Compiler @common @linkFlags @objects '-lgcc' '-o' $elf
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Size $elf
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Objdump '-d' '-S' $elf *> $disassembly
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Output "XPACK_ELF=$elf"
Write-Output "XPACK_FLAGS=-march=rv32im_zicsr -mabi=ilp32 -mcmodel=medany -msmall-data-limit=0 -O$OptLevel -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fdata-sections -ffunction-sections"
