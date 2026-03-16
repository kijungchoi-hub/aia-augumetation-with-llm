[CmdletBinding()]
param(
    [string]$InputCsv = ".\data\origin\stt_summary.csv",
    [string]$OutputDir = ".\data\processed",
    [string]$CacheDir = ".\data\cache\llm-augmentation",
    [string]$Model = "gpt-5.4",
    [string]$CodexCommand = "codex.cmd",
    [string]$SystemPromptPath = ".\prompts\stt-augmentation-system.txt",
    [string]$UserPromptTemplatePath = ".\prompts\stt-augmentation-user-template.txt",
    [int]$AugmentationsPerCase = 5,
    [int]$MaxRows = 0,
    [int]$RequestDelayMs = 0,
    [int]$MaxRetries = 3,
    [int]$CodexTimeoutSec = 300,
    [switch]$DisableCache
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ResolvedCodexCommand = (Get-Command $CodexCommand -ErrorAction Stop).Source

function NWS([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $t = $Text -replace "`r", "" -replace "[\t ]+", " " -replace "\n{3,}", "`n`n"
    return $t.Trim()
}

function Normalize-Stt([string]$Text) {
    $t = NWS $Text
    $t = $t -replace "\*{2,}", "****"
    $t = $t -replace "상담사\s*:", "상담사: " -replace "고객\s*:", "고객: " -replace ":\s{2,}", ": "
    return $t
}

function Normalize-Answer([string]$Text) {
    $t = (NWS $Text) -replace "\*{2,}", "****"
    return ($t -replace "\s+\.", "." -replace "\s+,", ",")
}

function Tokens([string]$KeywordText) {
    if ([string]::IsNullOrWhiteSpace($KeywordText)) { return @() }
    return @(($KeywordText -split "/|\r?\n" | ForEach-Object { NWS $_ } | Where-Object { $_ }) | Select-Object -Unique)
}

function Json($InputObject) {
    return ($InputObject | ConvertTo-Json -Depth 20 -Compress)
}

function To-StringArray($Value) {
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @((NWS $Value))
    }
    return @($Value | ForEach-Object {
        $item = NWS ([string]$_)
        if ($item) { $item }
    } | Select-Object -Unique)
}

function To-DoubleValue($Value, [double]$Default = 0.0) {
    if ($null -eq $Value) { return $Default }
    $number = 0.0
    if ([double]::TryParse(([string]$Value), [ref]$number)) { return $number }
    return $Default
}

function Strip-JsonFence([string]$Text) {
    $trimmed = NWS $Text
    if ($trimmed -match "^```(?:json)?\s*(.+?)\s*```$") {
        return $matches[1]
    }
    return $trimmed
}

function Resolve-RepoPath([string]$PathValue) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $PathValue }
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    $repoRoot = Split-Path -Parent $PSScriptRoot
    return Join-Path $repoRoot $PathValue
}
function Get-CachePath([string]$CaseId, [string]$ModelName, [int]$VariantCount) {
    $safeModel = ($ModelName -replace "[^a-zA-Z0-9._-]", "_")
    $safeCase = ($CaseId -replace "[^a-zA-Z0-9._-]", "_")
    return Join-Path $CacheDir ("{0}__{1}__{2}.json" -f $safeCase, $safeModel, $VariantCount)
}

function Invoke-CodexChatJson([string]$SystemPrompt, [string]$UserPrompt, [string]$CaseId) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $tempDir = Join-Path $CacheDir "_codex_tmp"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    $safeCase = $CaseId -replace "[^a-zA-Z0-9._-]", "_"
    $requestId = "{0}_{1}" -f $safeCase, ([guid]::NewGuid().ToString("N"))
    $promptPath = Join-Path $tempDir ("prompt_{0}.txt" -f $requestId)
    $outputPath = Join-Path $tempDir ("response_{0}.json" -f $requestId)
    $stdoutPath = Join-Path $tempDir ("stdout_{0}.log" -f $requestId)
    $stderrPath = Join-Path $tempDir ("stderr_{0}.log" -f $requestId)
    $combinedPrompt = @"
$SystemPrompt

$UserPrompt
"@
    Set-Content -LiteralPath $promptPath -Value $combinedPrompt -Encoding UTF8

    $attempt = 1
    while ($true) {
        try {
            foreach ($pathToClear in @($outputPath, $stdoutPath, $stderrPath)) {
                if (Test-Path -LiteralPath $pathToClear) {
                    Remove-Item -LiteralPath $pathToClear -Force
                }
            }

            $cmdLine = ('type "{0}" | "{1}" exec -m "{2}" --skip-git-repo-check -C "{3}" -o "{4}" - >nul 2>"{5}"' -f $promptPath, $ResolvedCodexCommand, $Model, $repoRoot, $outputPath, $stderrPath)
            & cmd.exe /d /c $cmdLine | Out-Null
            if (-not (Test-Path -LiteralPath $outputPath)) {
                throw "Codex output file was not created: $outputPath"
            }

            $content = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8
            return (ConvertFrom-Json -InputObject (Strip-JsonFence $content))
        } catch {
            if ($attempt -ge $MaxRetries) { throw }
            Start-Sleep -Seconds ([Math]::Min(2 * $attempt, 8))
            $attempt++
        }
    }
}

function Validate([string]$OriginalText, [string]$CandidateText, $Slots) {
    $reasons = New-Object System.Collections.Generic.List[string]
    $paymentAmounts = @(To-StringArray $Slots.payment_amounts)
    $dateValues = @(To-StringArray $Slots.date_values)
    $contractCount = NWS ([string]$Slots.contract_count)
    foreach ($amount in $paymentAmounts) {
        if ($amount -and $OriginalText -match [regex]::Escape($amount) -and $CandidateText -notmatch [regex]::Escape($amount)) {
            $reasons.Add("amount_mismatch")
        }
    }
    if ($contractCount -and $OriginalText -match [regex]::Escape($contractCount) -and $CandidateText -notmatch [regex]::Escape($contractCount)) {
        $reasons.Add("contract_count_mismatch")
    }
    foreach ($dateValue in $dateValues) {
        if ($dateValue -and $OriginalText -match [regex]::Escape($dateValue) -and $CandidateText -notmatch [regex]::Escape($dateValue)) {
            $reasons.Add("date_mismatch")
        }
    }
    if ($CandidateText -match "\[MASK\]") { $reasons.Add("mask_not_normalized") }
    if ($CandidateText.Length -lt 20) { $reasons.Add("too_short") }
    $hallucination = ($CandidateText -match "완료") -and ($OriginalText -notmatch "완료|발송|처리|입금")
    return @{
        pass = ($reasons.Count -eq 0)
        reasons = @($reasons | Select-Object -Unique)
        hallucination_risk = $hallucination
    }
}

function Merge-Validation($Left, $Right) {
    return @{
        pass = ([bool]$Left.pass -and [bool]$Right.pass)
        reasons = @((@($Left.reasons) + @($Right.reasons)) | Where-Object { $_ } | Select-Object -Unique)
        hallucination_risk = ([bool]$Left.hallucination_risk -or [bool]$Right.hallucination_risk)
    }
}

function Confidence($Slots, [object[]]$KeywordLabels, $Validation) {
    $s = 0.58
    if (NWS ([string]$Slots.contract_count)) { $s += 0.06 }
    if (@(To-StringArray $Slots.payment_amounts).Count -gt 0) { $s += 0.08 }
    if (@(To-StringArray $Slots.date_values).Count -gt 0) { $s += 0.05 }
    if (@(To-StringArray $Slots.actions).Count -gt 0) { $s += 0.06 }
    if (@(To-StringArray $Slots.outcomes).Count -gt 0) { $s += 0.05 }
    if (@($KeywordLabels).Count -ge 3) { $s += 0.06 }
    if ($Validation.pass) { $s += 0.07 } else { $s -= 0.12 }
    if ($Validation.hallucination_risk) { $s -= 0.08 }
    return [math]::Round(([math]::Max([math]::Min($s, 0.98), 0.35)), 2)
}

function Grade([string]$RowType, [double]$Confidence, [bool]$ValidationPass) {
    if ($RowType -eq "base") { return "Gold" }
    if ($ValidationPass -and $Confidence -ge 0.8) { return "Silver" }
    return "Weak"
}

function AutoLabels([string]$CaseId, $Summary, [object[]]$KeywordLabels, [string]$IntentType, $Validation, [double]$Confidence) {
    return [ordered]@{
        call_id = $CaseId
        auto_labels = [ordered]@{
            summary_label = [ordered]@{
                text = [string]$Summary.standard_text
                short_text = [string]$Summary.short_text
                method = "llm_structured_v1"
                confidence = $Confidence
            }
            keyword_labels = @($KeywordLabels)
            issue_type = [ordered]@{
                label = $IntentType
                confidence = [math]::Round(([math]::Min($Confidence + 0.03, 0.99)), 2)
            }
            quality_tags = [ordered]@{
                missing_slots = @($Validation.reasons | Where-Object { $_ -match "mismatch" })
                hallucination_risk = $Validation.hallucination_risk
                validation_pass = $Validation.pass
                validation_reasons = @($Validation.reasons)
            }
        }
    }
}

function New-DefaultUtteranceLabels([string]$SttText) {
    $labels = New-Object System.Collections.Generic.List[object]
    $index = 1
    foreach ($line in ($SttText -split "`n")) {
        $trimmed = NWS $line
        if (-not $trimmed) { continue }
        $speaker = "미상"
        $text = $trimmed
        if ($trimmed -match "^(상담사|고객)\s*:\s*(.+)$") {
            $speaker = $matches[1]
            $text = NWS $matches[2]
        }
        $labels.Add([pscustomobject]@{
            utterance_id = $index
            speaker = $speaker
            label = "일반발화"
            text = $text
        })
        $index++
    }
    return $labels.ToArray()
}

function Sanitize-KeywordLabels($Items, [string]$IntentType, [string]$EvidenceText) {
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Items)) {
        $keyword = NWS ([string]$item.keyword)
        if (-not $keyword) { continue }
        $canonical = NWS ([string]$item.canonical)
        $type = NWS ([string]$item.type)
        $source = NWS ([string]$item.source)
        $evidence = NWS ([string]$item.evidence_span)
        $result.Add([pscustomobject]@{
            keyword = $keyword
            canonical = if ($canonical) { $canonical } else { $keyword }
            type = if ($type) { $type } else { "raw" }
            source = if ($source) { $source } else { "llm" }
            confidence = [math]::Round(([math]::Max([math]::Min((To-DoubleValue $item.confidence 0.85), 1.0), 0.0)), 2)
            evidence_span = if ($evidence) { $evidence } elseif ($EvidenceText -match [regex]::Escape($keyword)) { $keyword } else { $keyword }
        })
    }
    if (-not ($result | Where-Object { $_.canonical -eq $IntentType -and $_.type -eq "intent" })) {
        $result.Add([pscustomobject]@{
            keyword = $IntentType
            canonical = $IntentType
            type = "intent"
            source = "llm_intent"
            confidence = 0.9
            evidence_span = $IntentType
        })
    }
    return $result.ToArray()
}

function Sanitize-Slots($Slots, [string]$IntentType, [string[]]$FallbackKeywords) {
    $slotIntent = NWS ([string]$Slots.intent_type)
    $requestType = NWS ([string]$Slots.request_type)
    $slotKeywords = @(To-StringArray $Slots.keywords)
    return [ordered]@{
        intent_type = if ($slotIntent) { $slotIntent } else { $IntentType }
        request_type = if ($requestType) { $requestType } else { $IntentType }
        contract_count = NWS ([string]$Slots.contract_count)
        payment_amounts = @(To-StringArray $Slots.payment_amounts)
        date_values = @(To-StringArray $Slots.date_values)
        institutions = @(To-StringArray $Slots.institutions)
        channels = @(To-StringArray $Slots.channels)
        documents = @(To-StringArray $Slots.documents)
        actions = @(To-StringArray $Slots.actions)
        outcomes = @(To-StringArray $Slots.outcomes)
        product_names = @(To-StringArray $Slots.product_names)
        keywords = if (@($slotKeywords).Count -gt 0) { $slotKeywords } else { @($FallbackKeywords) }
    }
}

function Sanitize-Summary($Summary, [string]$AnswerStandardized, [string]$AnswerShort, [string]$IntentType, $Slots) {
    $slotSummary = $Summary.slot_summary
    return [ordered]@{
        customer_intent = if (NWS ([string]$Summary.customer_intent)) { NWS ([string]$Summary.customer_intent) } else { "$IntentType 관련 요청" }
        agent_action = if (NWS ([string]$Summary.agent_action)) { NWS ([string]$Summary.agent_action) } else { "상담사가 처리 또는 안내함" }
        result = if (NWS ([string]$Summary.result)) { NWS ([string]$Summary.result) } else { "처리 결과를 정리함" }
        short_text = if (NWS ([string]$Summary.short_text)) { Normalize-Answer ([string]$Summary.short_text) } else { $AnswerShort }
        standard_text = if (NWS ([string]$Summary.standard_text)) { Normalize-Answer ([string]$Summary.standard_text) } else { $AnswerStandardized }
        slot_summary = [ordered]@{
            request_type = if (NWS ([string]$slotSummary.request_type)) { NWS ([string]$slotSummary.request_type) } else { [string]$Slots.request_type }
            target_product = if (NWS ([string]$slotSummary.target_product)) { NWS ([string]$slotSummary.target_product) } else { ((To-StringArray $Slots.product_names) -join ", ") }
            agent_action = if (NWS ([string]$slotSummary.agent_action)) { NWS ([string]$slotSummary.agent_action) } else { ((To-StringArray $Slots.actions) -join ", ") }
            result = if (NWS ([string]$slotSummary.result)) { NWS ([string]$slotSummary.result) } else { ((To-StringArray $Slots.outcomes) -join ", ") }
        }
    }
}

function Sanitize-Variants($Variants, [int]$Count, [string]$BaseStt, [string]$BaseGold, [string]$BaseStandardized, [string]$BaseShort) {
    $targetTypes = @("clean", "paraphrase_service", "paraphrase_customer", "answer_polite", "answer_compact", "summary_short")
    $sanitized = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($variant in @($Variants)) {
        if ($index -ge $Count) { break }
        $augType = NWS ([string]$variant.aug_type)
        if (-not $augType) { $augType = $targetTypes[$index] }
        $answerStyle = NWS ([string]$variant.answer_style)
        if (-not $answerStyle) {
            $answerStyle = if ($augType -eq "summary_short") { "short" } elseif ($augType -eq "answer_polite") { "polite" } elseif ($augType -eq "answer_compact") { "compact" } else { "gold" }
        }
        $answerGold = if (NWS ([string]$variant.answer_gold)) { Normalize-Answer ([string]$variant.answer_gold) } elseif ($answerStyle -eq "short") { $BaseShort } else { $BaseGold }
        $answerStandardized = if (NWS ([string]$variant.answer_standardized)) { Normalize-Answer ([string]$variant.answer_standardized) } elseif ($answerStyle -eq "short") { $BaseShort } else { $BaseStandardized }
        $answerShort = if (NWS ([string]$variant.answer_short)) { Normalize-Answer ([string]$variant.answer_short) } else { $BaseShort }
        $sttText = if ($augType -like "answer_*") { $BaseStt } elseif (NWS ([string]$variant.stt_text)) { Normalize-Stt ([string]$variant.stt_text) } else { $BaseStt }
        $sanitized.Add([pscustomobject]@{
            aug_type = $augType
            answer_style = $answerStyle
            stt_text = $sttText
            answer_gold = $answerGold
            answer_standardized = $answerStandardized
            answer_short = $answerShort
        })
        $index++
    }

    while ($sanitized.Count -lt $Count) {
        $fallbackType = $targetTypes[$sanitized.Count]
        $sanitized.Add([pscustomobject]@{
            aug_type = $fallbackType
            answer_style = if ($fallbackType -eq "summary_short") { "short" } elseif ($fallbackType -eq "answer_polite") { "polite" } elseif ($fallbackType -eq "answer_compact") { "compact" } else { "gold" }
            stt_text = $BaseStt
            answer_gold = if ($fallbackType -eq "summary_short") { $BaseShort } elseif ($fallbackType -like "answer_*") { $BaseGold } else { $BaseGold }
            answer_standardized = if ($fallbackType -eq "summary_short") { $BaseShort } elseif ($fallbackType -like "answer_*") { $BaseStandardized } else { $BaseStandardized }
            answer_short = $BaseShort
        })
    }

    return $sanitized.ToArray()
}

function Get-LlmAugmentation($Row, [int]$VariantCount) {
    $caseId = [string]$Row.케이스ID
    $cachePath = Get-CachePath -CaseId $caseId -ModelName $Model -VariantCount $VariantCount
    if (-not $DisableCache -and (Test-Path -LiteralPath $cachePath)) {
        $cachedRaw = Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($cachedRaw)) {
            try {
                return (ConvertFrom-Json -InputObject $cachedRaw)
            } catch {
                Remove-Item -LiteralPath $cachePath -Force -ErrorAction SilentlyContinue
            }
        } else {
            Remove-Item -LiteralPath $cachePath -Force -ErrorAction SilentlyContinue
        }
    }
    $systemPrompt = Get-Content -LiteralPath (Resolve-RepoPath $SystemPromptPath) -Raw -Encoding UTF8
    $userTemplate = Get-Content -LiteralPath (Resolve-RepoPath $UserPromptTemplatePath) -Raw -Encoding UTF8
    $userPrompt = $userTemplate.Replace("__CASE_ID__", [string]$Row.케이스ID).
        Replace("__VARIANT_COUNT__", [string]$VariantCount).
        Replace("__STT_TEXT__", [string]$Row.STT전문).
        Replace("__LLM_ANSWER__", [string]$Row.LLM답변).
        Replace("__ANSWER_GOLD__", [string]$Row.정답지).
        Replace("__KEYWORD_HINT__", [string]$Row.키워드)

    $payload = Invoke-CodexChatJson -SystemPrompt $systemPrompt -UserPrompt $userPrompt -CaseId $caseId
    if (-not $DisableCache) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
        Set-Content -LiteralPath $cachePath -Value (Json $payload) -Encoding UTF8
    }
    if ($RequestDelayMs -gt 0) {
        Start-Sleep -Milliseconds $RequestDelayMs
    }
    return $payload
}

if (-not (Test-Path -LiteralPath $InputCsv)) { throw "Input CSV not found: $InputCsv" }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$rows = @(Import-Csv -Path $InputCsv)
if ($MaxRows -gt 0) {
    $rows = @($rows | Select-Object -First $MaxRows)
}

$baseClean = New-Object System.Collections.Generic.List[object]
$baseNormalized = New-Object System.Collections.Generic.List[object]
$augmented = New-Object System.Collections.Generic.List[object]

foreach ($row in $rows) {
    $caseId = [string]$row.케이스ID
    $stt = Normalize-Stt $row.STT전문
    $llm = Normalize-Answer $row.LLM답변
    $answer = Normalize-Answer $row.정답지
    $fallbackKeywords = Tokens $row.키워드

    $llmPayload = Get-LlmAugmentation -Row $row -VariantCount $AugmentationsPerCase

    $intent = if (NWS ([string]$llmPayload.intent_type)) { NWS ([string]$llmPayload.intent_type) } else { "기타" }
    $answerGold = if (NWS ([string]$llmPayload.answer_gold)) { Normalize-Answer ([string]$llmPayload.answer_gold) } else { $answer }
    $answerStandardized = if (NWS ([string]$llmPayload.answer_standardized)) { Normalize-Answer ([string]$llmPayload.answer_standardized) } else { $answerGold }
    $answerShort = if (NWS ([string]$llmPayload.answer_short)) { Normalize-Answer ([string]$llmPayload.answer_short) } else { $answerGold }
    $slots = Sanitize-Slots -Slots $llmPayload.keyword_slots -IntentType $intent -FallbackKeywords $fallbackKeywords
    $summary = Sanitize-Summary -Summary $llmPayload.summary_structured -AnswerStandardized $answerStandardized -AnswerShort $answerShort -IntentType $intent -Slots $slots
    $keywordLabels = @(Sanitize-KeywordLabels -Items $llmPayload.keyword_labels -IntentType $intent -EvidenceText (($stt + " " + $answerGold + " " + ($fallbackKeywords -join " "))))
    $utteranceLabels = @($llmPayload.utterance_labels)
    if (@($utteranceLabels).Count -eq 0) {
        $utteranceLabels = @(New-DefaultUtteranceLabels $stt)
    }
    $variants = @(Sanitize-Variants -Variants $llmPayload.variants -Count $AugmentationsPerCase -BaseStt $stt -BaseGold $answerGold -BaseStandardized $answerStandardized -BaseShort $answerShort)

    $baseValidation = Merge-Validation (Validate $stt $stt $slots) (Validate $answer $answerStandardized $slots)
    $baseConfidence = Confidence $slots $keywordLabels $baseValidation
    $baseGrade = Grade "base" $baseConfidence $baseValidation.pass

    $slotJson = Json $slots
    $summaryJson = Json $summary
    $keywordJson = Json $keywordLabels
    $utteranceJson = Json $utteranceLabels
    $autoJson = Json (AutoLabels $caseId $summary $keywordLabels $intent $baseValidation $baseConfidence)

    $baseClean.Add([pscustomobject]@{
        case_id = $caseId
        stt_text = $stt
        llm_answer = $llm
        answer_gold = $answerGold
        keyword_raw = $row.키워드
        utterance_count = @($utteranceLabels).Count
    })

    $baseNormalized.Add([pscustomobject]@{
        case_id = $caseId
        intent_type = $intent
        label_grade = $baseGrade
        label_confidence = $baseConfidence
        stt_text = $stt
        llm_answer = $llm
        answer_gold = $answerGold
        answer_standardized = $answerStandardized
        answer_short = $answerShort
        summary_structured = $summaryJson
        keyword_raw = $row.키워드
        keyword_tokens = (($slots.keywords) -join " | ")
        keyword_slots = $slotJson
        keyword_labels = $keywordJson
        utterance_labels = $utteranceJson
        auto_label_json = $autoJson
        validation_pass = $baseValidation.pass
        validation_reason = if ($baseValidation.reasons.Count -gt 0) { ($baseValidation.reasons -join "|") } else { "ok" }
    })

    $variantIndex = 1
    foreach ($variant in $variants) {
        $variantValidation = Merge-Validation (Validate $stt $variant.stt_text $slots) (Validate $answer $variant.answer_gold $slots)
        $variantConfidence = Confidence $slots $keywordLabels $variantValidation
        $variantGrade = Grade "augmented" $variantConfidence $variantValidation.pass
        $variantSummary = Sanitize-Summary -Summary ([pscustomobject]@{
            customer_intent = $summary.customer_intent
            agent_action = $summary.agent_action
            result = $summary.result
            short_text = $variant.answer_short
            standard_text = $variant.answer_standardized
            slot_summary = $summary.slot_summary
        }) -AnswerStandardized $variant.answer_standardized -AnswerShort $variant.answer_short -IntentType $intent -Slots $slots

        $augmented.Add([pscustomobject]@{
            source_case_id = $caseId
            aug_id = ("{0}-{1:D2}" -f $caseId, $variantIndex)
            aug_type = $variant.aug_type
            answer_style = $variant.answer_style
            intent_type = $intent
            label_grade = $variantGrade
            label_confidence = $variantConfidence
            stt_text = $variant.stt_text
            answer_gold = $variant.answer_gold
            answer_standardized = $variant.answer_standardized
            answer_short = $variant.answer_short
            keyword_raw = $row.키워드
            keyword_slots = $slotJson
            keyword_labels = $keywordJson
            utterance_labels = $utteranceJson
            auto_label_json = (Json (AutoLabels $caseId $variantSummary $keywordLabels $intent $variantValidation $variantConfidence))
            validation_pass = $variantValidation.pass
            validation_reason = if ($variantValidation.reasons.Count -gt 0) { ($variantValidation.reasons -join "|") } else { "ok" }
        })
        $variantIndex++
    }
}

$validated = @($augmented | Where-Object { $_.validation_pass -eq $true -and $_.label_grade -eq "Silver" })

$baseClean | Export-Csv -Path (Join-Path $OutputDir "base_clean.csv") -NoTypeInformation -Encoding utf8
$baseNormalized | Export-Csv -Path (Join-Path $OutputDir "base_normalized.csv") -NoTypeInformation -Encoding utf8
$augmented | Export-Csv -Path (Join-Path $OutputDir "augmented_dataset.csv") -NoTypeInformation -Encoding utf8
$validated | Export-Csv -Path (Join-Path $OutputDir "augmented_validated.csv") -NoTypeInformation -Encoding utf8

Write-Output ("Generated base_clean.csv rows={0}" -f $baseClean.Count)
Write-Output ("Generated base_normalized.csv rows={0}" -f $baseNormalized.Count)
Write-Output ("Generated augmented_dataset.csv rows={0}" -f $augmented.Count)
Write-Output ("Generated augmented_validated.csv rows={0}" -f $validated.Count)


























