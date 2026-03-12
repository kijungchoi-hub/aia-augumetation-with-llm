[CmdletBinding()]
param(
    [string]$SplitsDir = '.\data\splits',
    [string]$OutputRoot = '.\data\versions'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function New-VersionDir([string]$Path) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Copy-BaseFiles([string]$SourceDir, [string]$TargetDir) {
    foreach ($name in @('base_train.csv','base_valid.csv','base_test.csv')) {
        Copy-Item -Path (Join-Path $SourceDir $name) -Destination (Join-Path $TargetDir $name) -Force
    }
}

function Expand-TrainingRows {
    param(
        [object[]]$Rows,
        [int]$Copies,
        [string]$VersionTag
    )

    $expanded = New-Object System.Collections.Generic.List[object]
    $index = 1
    foreach ($row in $Rows) {
        for ($copy = 1; $copy -le $Copies; $copy++) {
            $sampleId = if ($row.sample_id) { '{0}_{1}_{2:D5}' -f $row.sample_id, $VersionTag, $copy } else { '{0}_{1:D5}' -f $VersionTag, $index }
            $augType = if ($row.aug_type -eq 'original') { 'original' } else { '{0}_{1}' -f $row.aug_type, $VersionTag }
            $expanded.Add([pscustomobject]@{
                split = $row.split
                sample_id = $sampleId
                source_case_id = $row.source_case_id
                aug_type = $augType
                answer_style = $row.answer_style
                intent_type = $row.intent_type
                label_grade = $row.label_grade
                label_confidence = $row.label_confidence
                stt_text = $row.stt_text
                answer_gold = $row.answer_gold
                answer_standardized = $row.answer_standardized
                answer_short = $row.answer_short
                keyword_raw = $row.keyword_raw
                keyword_slots = $row.keyword_slots
                keyword_labels = $row.keyword_labels
                utterance_labels = $row.utterance_labels
                auto_label_json = $row.auto_label_json
            })
            $index++
        }
    }
    return $expanded.ToArray()
}

if (-not (Test-Path $SplitsDir)) { throw "Splits directory not found: $SplitsDir" }
New-VersionDir -Path $OutputRoot

$baseTrain = Import-Csv (Join-Path $SplitsDir 'base_train.csv')
$baseValid = Import-Csv (Join-Path $SplitsDir 'base_valid.csv')
$baseTest = Import-Csv (Join-Path $SplitsDir 'base_test.csv')
$trainAug = Import-Csv (Join-Path $SplitsDir 'train_augmented.csv')
$trainFinal = Import-Csv (Join-Path $SplitsDir 'train_final.csv')

$versions = @(
    @{ Name = 'ver1.0'; Copies = 1 }
    @{ Name = 'ver1.1'; Copies = 2 }
    @{ Name = 'ver1.2'; Copies = 4 }
)

foreach ($version in $versions) {
    $versionDir = Join-Path $OutputRoot $version.Name
    New-VersionDir -Path $versionDir

    $baseTrain | Export-Csv (Join-Path $versionDir 'base_train.csv') -NoTypeInformation -Encoding utf8
    $baseValid | Export-Csv (Join-Path $versionDir 'base_valid.csv') -NoTypeInformation -Encoding utf8
    $baseTest | Export-Csv (Join-Path $versionDir 'base_test.csv') -NoTypeInformation -Encoding utf8

    $versionTrainAug = Expand-TrainingRows -Rows $trainAug -Copies $version.Copies -VersionTag $version.Name
    $versionTrainFinal = Expand-TrainingRows -Rows $trainFinal -Copies $version.Copies -VersionTag $version.Name

    $versionTrainAug | Export-Csv (Join-Path $versionDir 'train_augmented.csv') -NoTypeInformation -Encoding utf8
    $versionTrainFinal | Export-Csv (Join-Path $versionDir 'train_final.csv') -NoTypeInformation -Encoding utf8

    [pscustomobject]@{
        version = $version.Name
        multiplier = $version.Copies
        base_train_rows = $baseTrain.Count
        base_valid_rows = $baseValid.Count
        base_test_rows = $baseTest.Count
        train_augmented_rows = $versionTrainAug.Count
        train_final_rows = $versionTrainFinal.Count
    } | Export-Csv (Join-Path $versionDir 'manifest.csv') -NoTypeInformation -Encoding utf8

    Write-Output ('Generated {0} train_augmented={1} train_final={2}' -f $version.Name, $versionTrainAug.Count, $versionTrainFinal.Count)
}
