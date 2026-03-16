[CmdletBinding()]
param(
    [string]$SourceRoot = "data/versions",
    [string]$OutputRoot = "web/review-data",
    [string]$OriginCsv = "data/origin/stt_summary.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,
        [Parameter(Mandatory = $true)]
        [string[]]$CandidateNames
    )

    foreach ($candidateName in $CandidateNames) {
        $property = $InputObject.PSObject.Properties[$candidateName]
        if ($null -ne $property) {
            return [string]$property.Value
        }
    }

    return ""
}

function New-SafeAssetName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [Parameter(Mandatory = $true)]
        [string]$FileBaseName
    )

    return (($Version -replace "[^a-zA-Z0-9._-]", "_") + "__" + ($FileBaseName -replace "[^a-zA-Z0-9._-]", "_") + ".js")
}

function ConvertTo-JavaScriptAssignment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Expression,
        [Parameter(Mandatory = $true)]
        $Value
    )

    $json = $Value | ConvertTo-Json -Depth 20 -Compress
    return "$Expression = $json;"
}

if (-not (Test-Path -LiteralPath $SourceRoot)) {
    throw "Source root not found: $SourceRoot"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$originSttByCaseId = @{}
if (Test-Path -LiteralPath $OriginCsv) {
    $originRows = @(Import-Csv -LiteralPath $OriginCsv)
    foreach ($originRow in $originRows) {
        $caseId = Get-PropertyValue -InputObject $originRow -CandidateNames @("케이스ID", "case_id", "source_case_id", "sample_id")
        if (-not [string]::IsNullOrWhiteSpace($caseId)) {
            $originSttByCaseId[$caseId] = Get-PropertyValue -InputObject $originRow -CandidateNames @("STT전문", "stt_text", "text", "utterance")
        }
    }
}

$indexEntries = New-Object System.Collections.Generic.List[object]
$versionDirs = Get-ChildItem -LiteralPath $SourceRoot -Directory | Sort-Object Name

foreach ($versionDir in $versionDirs) {
    $csvFiles = Get-ChildItem -LiteralPath $versionDir.FullName -Filter "*.csv" -File | Sort-Object Name

    foreach ($csvFile in $csvFiles) {
        $rows = @(Import-Csv -LiteralPath $csvFile.FullName)
        $firstRow = $rows | Select-Object -First 1
        $columns = @()
        if ($null -ne $firstRow) {
            $columns = @($firstRow.PSObject.Properties.Name)
        }

        $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($csvFile.Name)
        $datasetKey = "$($versionDir.Name)/$fileBaseName"
        $assetFileName = New-SafeAssetName -Version $versionDir.Name -FileBaseName $fileBaseName
        $assetPath = Join-Path $OutputRoot $assetFileName

        $payload = [ordered]@{
            key = $datasetKey
            version = $versionDir.Name
            fileName = $csvFile.Name
            fileBaseName = $fileBaseName
            rowCount = $rows.Count
            columns = $columns
            rows = @(
                for ($index = 0; $index -lt $rows.Count; $index++) {
                    $valueMap = [ordered]@{}
                    foreach ($property in $rows[$index].PSObject.Properties) {
                        $valueMap[$property.Name] = $property.Value
                    }

                    $sourceCaseId = [string]$valueMap["source_case_id"]
                    if ([string]::IsNullOrWhiteSpace($sourceCaseId)) {
                        $sourceCaseId = [string]$valueMap["sample_id"]
                    }

                    [ordered]@{
                        rowIndex = $index + 1
                        values = $valueMap
                        originSttText = if ($originSttByCaseId.ContainsKey($sourceCaseId)) { $originSttByCaseId[$sourceCaseId] } else { "" }
                    }
                }
            )
        }

        $scriptBody = @(
            "window.QUALITY_REVIEW_DATA = window.QUALITY_REVIEW_DATA || {};"
            (ConvertTo-JavaScriptAssignment -Expression "window.QUALITY_REVIEW_DATA[`"$datasetKey`"]" -Value $payload)
        ) -join [Environment]::NewLine

        Set-Content -LiteralPath $assetPath -Value $scriptBody -Encoding UTF8

        $indexEntries.Add([ordered]@{
            key = $datasetKey
            version = $versionDir.Name
            fileName = $csvFile.Name
            fileBaseName = $fileBaseName
            rowCount = $rows.Count
            columns = $columns
            assetFile = $assetFileName
        }) | Out-Null
    }
}

$indexScript = ConvertTo-JavaScriptAssignment -Expression "window.QUALITY_REVIEW_INDEX" -Value @{
    generatedAt = (Get-Date).ToString("s")
    sourceRoot = $SourceRoot
    datasets = $indexEntries
}

Set-Content -LiteralPath (Join-Path $OutputRoot "index.js") -Value $indexScript -Encoding UTF8
Write-Host "Generated quality review assets in $OutputRoot"

