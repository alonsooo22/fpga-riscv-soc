[CmdletBinding()]
param(
    [ValidateSet('BuildModel', 'RunIntegration', 'RunKernel', 'RunKernelSet', 'RunReferenceR')]
    [string]$Action = 'BuildModel',
    [ValidateSet('ALL', 'E', 'D', 'A')]
    [string]$Group = 'ALL',
    [ValidateSet('E', 'D', 'DP', 'A', 'EDA', 'EDAP')]
    [string]$Variant = 'E'
)

$ErrorActionPreference = 'Stop'
$helper = 'D:\code\FPGA\vivado\ultra_bht_btb_followup\scripts\ultra_dev.ps1'
$command = switch ($Action) {
    'BuildModel' { "bash /work/ultra_simd_subset_v1/scripts/run_rtl_candidate.sh BuildModel $Group" }
    'RunIntegration' { "bash /work/ultra_simd_subset_v1/scripts/run_rtl_candidate.sh RunIntegration $Group" }
    'RunKernel' { "bash /work/ultra_simd_subset_v1/scripts/run_rtl_candidate.sh RunKernel $Group $Variant" }
    'RunKernelSet' { "bash /work/ultra_simd_subset_v1/scripts/run_rtl_candidate.sh RunKernelSet $Group" }
    'RunReferenceR' { 'bash /work/ultra_simd_subset_v1/scripts/run_rtl_candidate.sh RunReferenceR' }
}
& $helper -Action Exec -Command $command
