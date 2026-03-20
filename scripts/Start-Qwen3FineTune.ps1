[CmdletBinding()]
param(
    [string]$ModelNameOrPath = 'Qwen/Qwen3-4B-Instruct',
    [string]$DatasetDir = '.\data\finetune\qwen3\sft',
    [string]$OutputDir = '.\data\finetune\qwen3\outputs\qwen3-sft',
    [ValidateSet('lora', 'full')]
    [string]$TuningMode = 'lora',
    [int]$MaxSeqLength = 2048,
    [int]$PerDeviceTrainBatchSize = 1,
    [int]$PerDeviceEvalBatchSize = 1,
    [int]$GradientAccumulationSteps = 8,
    [double]$LearningRate = 2e-4,
    [double]$NumTrainEpochs = 3.0,
    [double]$WarmupRatio = 0.03,
    [int]$LoggingSteps = 10,
    [int]$SaveSteps = 100,
    [int]$EvalSteps = 100,
    [int]$SaveTotalLimit = 2,
    [int]$LoraR = 16,
    [int]$LoraAlpha = 32,
    [double]$LoraDropout = 0.05,
    [string]$LoraTargetModules = 'q_proj,k_proj,v_proj,o_proj,gate_proj,up_proj,down_proj',
    [switch]$LoadIn4bit,
    [switch]$Packing,
    [switch]$TrustRemoteCode,
    [switch]$Bf16,
    [switch]$Fp16,
    [string]$PythonCommand = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Resolve-PythonCommand([string]$Requested) {
    $candidates = @()
    if ($Requested) { $candidates += $Requested }
    $candidates += @(
        'C:\Program Files\Orange\python.exe',
        'C:\Users\kijungchoi\yolovenv\Scripts\python.exe',
        'python'
    )

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (-not $candidate) { continue }
        if (Test-Path $candidate) { return $candidate }
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }

    throw 'No usable Python interpreter found. Set -PythonCommand explicitly.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$trainScript = Join-Path $repoRoot 'training\qwen3_finetune\train.py'
$resolvedDatasetDir = Join-Path $repoRoot $DatasetDir
$resolvedOutputDir = Join-Path $repoRoot $OutputDir
$resolvedPython = Resolve-PythonCommand $PythonCommand

$argsList = @(
    $trainScript,
    '--model-name-or-path', $ModelNameOrPath,
    '--train-file', (Join-Path $resolvedDatasetDir 'train.jsonl'),
    '--valid-file', (Join-Path $resolvedDatasetDir 'valid.jsonl'),
    '--output-dir', $resolvedOutputDir,
    '--tuning-mode', $TuningMode,
    '--max-seq-length', [string]$MaxSeqLength,
    '--per-device-train-batch-size', [string]$PerDeviceTrainBatchSize,
    '--per-device-eval-batch-size', [string]$PerDeviceEvalBatchSize,
    '--gradient-accumulation-steps', [string]$GradientAccumulationSteps,
    '--learning-rate', [string]$LearningRate,
    '--num-train-epochs', [string]$NumTrainEpochs,
    '--warmup-ratio', [string]$WarmupRatio,
    '--logging-steps', [string]$LoggingSteps,
    '--save-steps', [string]$SaveSteps,
    '--eval-steps', [string]$EvalSteps,
    '--save-total-limit', [string]$SaveTotalLimit,
    '--lora-r', [string]$LoraR,
    '--lora-alpha', [string]$LoraAlpha,
    '--lora-dropout', [string]$LoraDropout,
    '--lora-target-modules', $LoraTargetModules
)

if ($LoadIn4bit) { $argsList += '--load-in-4bit' }
if ($Packing) { $argsList += '--packing' }
if ($TrustRemoteCode) { $argsList += '--trust-remote-code' }
if ($Bf16) { $argsList += '--bf16' }
if ($Fp16) { $argsList += '--fp16' }

& $resolvedPython @argsList
