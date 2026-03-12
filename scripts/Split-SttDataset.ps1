[CmdletBinding()]
param(
    [string]$BaseNormalizedCsv = ".\data\processed\base_normalized.csv",
    [string]$AugmentedValidatedCsv = ".\data\processed\augmented_validated.csv",
    [string]$OutputDir = ".\data\splits"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Get-SplitName([string]$CaseId) {
    $number = 0
    [void][int]::TryParse($CaseId, [ref]$number)
    $bucket = $number % 10
    if ($bucket -eq 0) { return "test" }
    if ($bucket -eq 1) { return "valid" }
    return "train"
}

function Sanitize-Field($Value) {
    if ($null -eq $Value) { return $null }
    return ([string]$Value).Replace('[MASK]', '****')
}

if (-not (Test-Path $BaseNormalizedCsv)) { throw "Base normalized CSV not found: $BaseNormalizedCsv" }
if (-not (Test-Path $AugmentedValidatedCsv)) { throw "Augmented validated CSV not found: $AugmentedValidatedCsv" }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$baseRows = Import-Csv $BaseNormalizedCsv
$augRows = Import-Csv $AugmentedValidatedCsv

$baseWithSplit = foreach ($row in $baseRows) {
    [pscustomobject]@{
        split = Get-SplitName -CaseId $row.case_id
        sample_id = Sanitize-Field $row.case_id
        source_case_id = Sanitize-Field $row.case_id
        aug_type = "original"
        answer_style = "gold"
        intent_type = Sanitize-Field $row.intent_type
        label_grade = Sanitize-Field $row.label_grade
        label_confidence = Sanitize-Field $row.label_confidence
        stt_text = Sanitize-Field $row.stt_text
        answer_gold = Sanitize-Field $row.answer_gold
        answer_standardized = Sanitize-Field $row.answer_standardized
        answer_short = Sanitize-Field $row.answer_short
        keyword_raw = Sanitize-Field $row.keyword_raw
        keyword_slots = Sanitize-Field $row.keyword_slots
        keyword_labels = Sanitize-Field $row.keyword_labels
        utterance_labels = Sanitize-Field $row.utterance_labels
        auto_label_json = Sanitize-Field $row.auto_label_json
    }
}

$trainCaseIds = @($baseWithSplit | Where-Object { $_.split -eq 'train' } | ForEach-Object { $_.source_case_id })
$trainAugmented = foreach ($row in $augRows | Where-Object { $_.source_case_id -in $trainCaseIds }) {
    [pscustomobject]@{
        split = "train"
        sample_id = Sanitize-Field $row.aug_id
        source_case_id = Sanitize-Field $row.source_case_id
        aug_type = Sanitize-Field $row.aug_type
        answer_style = Sanitize-Field $row.answer_style
        intent_type = Sanitize-Field $row.intent_type
        label_grade = Sanitize-Field $row.label_grade
        label_confidence = Sanitize-Field $row.label_confidence
        stt_text = Sanitize-Field $row.stt_text
        answer_gold = Sanitize-Field $row.answer_gold
        answer_standardized = Sanitize-Field $row.answer_standardized
        answer_short = Sanitize-Field $row.answer_short
        keyword_raw = Sanitize-Field $row.keyword_raw
        keyword_slots = Sanitize-Field $row.keyword_slots
        keyword_labels = Sanitize-Field $row.keyword_labels
        utterance_labels = Sanitize-Field $row.utterance_labels
        auto_label_json = Sanitize-Field $row.auto_label_json
    }
}

$baseTrain = @($baseWithSplit | Where-Object { $_.split -eq 'train' })
$baseValid = @($baseWithSplit | Where-Object { $_.split -eq 'valid' })
$baseTest = @($baseWithSplit | Where-Object { $_.split -eq 'test' })
$trainFinal = @($baseTrain + $trainAugmented)

$baseTrain | Export-Csv (Join-Path $OutputDir 'base_train.csv') -NoTypeInformation -Encoding utf8
$baseValid | Export-Csv (Join-Path $OutputDir 'base_valid.csv') -NoTypeInformation -Encoding utf8
$baseTest | Export-Csv (Join-Path $OutputDir 'base_test.csv') -NoTypeInformation -Encoding utf8
$trainAugmented | Export-Csv (Join-Path $OutputDir 'train_augmented.csv') -NoTypeInformation -Encoding utf8
$trainFinal | Export-Csv (Join-Path $OutputDir 'train_final.csv') -NoTypeInformation -Encoding utf8

Write-Output ("Generated base_train.csv rows={0}" -f $baseTrain.Count)
Write-Output ("Generated base_valid.csv rows={0}" -f $baseValid.Count)
Write-Output ("Generated base_test.csv rows={0}" -f $baseTest.Count)
Write-Output ("Generated train_augmented.csv rows={0}" -f $trainAugmented.Count)
Write-Output ("Generated train_final.csv rows={0}" -f $trainFinal.Count)


