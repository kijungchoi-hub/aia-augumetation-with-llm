[CmdletBinding()]
param(
    [string]$TrainCsv = '.\data\versions\ver1.5\train_final.csv',
    [string]$ValidCsv = '.\data\versions\ver1.5\base_valid.csv',
    [string]$OutputDir = '.\data\finetune\qwen3\sft',
    [string]$TargetColumn = 'answer_standardized',
    [switch]$IncludeIntent,
    [switch]$IncludeKeywordSlots,
    [switch]$IncludeAnswerShortHint,
    [int]$MaxTrainRows = 0,
    [int]$MaxValidRows = 0,
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
$prepareScript = Join-Path $repoRoot 'training\qwen3_finetune\prepare_dataset.py'
$resolvedPython = Resolve-PythonCommand $PythonCommand

$argsList = @(
    $prepareScript,
    '--train-csv', (Join-Path $repoRoot $TrainCsv),
    '--valid-csv', (Join-Path $repoRoot $ValidCsv),
    '--output-dir', (Join-Path $repoRoot $OutputDir),
    '--target-column', $TargetColumn
)

if ($IncludeIntent) { $argsList += '--include-intent' }
if ($IncludeKeywordSlots) { $argsList += '--include-keyword-slots' }
if ($IncludeAnswerShortHint) { $argsList += '--include-answer-short-hint' }
if ($MaxTrainRows -gt 0) { $argsList += @('--max-train-rows', [string]$MaxTrainRows) }
if ($MaxValidRows -gt 0) { $argsList += @('--max-valid-rows', [string]$MaxValidRows) }

& $resolvedPython @argsList
