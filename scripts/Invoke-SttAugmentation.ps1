[CmdletBinding()]
param(
    [string]$InputCsv = ".\data\origin\stt_summary.csv",
    [string]$OutputDir = ".\data\processed",
    [string]$CacheDir = ".\data\cache\llm-augmentation",
    [string]$Model = "gpt-4.1-mini",
    [string]$ApiKey = "",
    [int]$AugmentationsPerCase = 5,
    [int]$MaxRows = 0,
    [int]$RequestDelayMs = 0,
    [int]$MaxRetries = 3,
    [switch]$DisableCache
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $ApiKey = [string]$env:OPENAI_API_KEY
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "OPENAI_API_KEY is required. Pass -ApiKey or set the OPENAI_API_KEY environment variable."
}

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

function Get-CachePath([string]$CaseId, [string]$ModelName, [int]$VariantCount) {
    $safeModel = ($ModelName -replace "[^a-zA-Z0-9._-]", "_")
    $safeCase = ($CaseId -replace "[^a-zA-Z0-9._-]", "_")
    return Join-Path $CacheDir ("{0}__{1}__{2}.json" -f $safeCase, $safeModel, $VariantCount)
}

function Invoke-OpenAIJson([string]$SystemPrompt, [string]$UserPrompt) {
    $uri = "https://api.openai.com/v1/chat/completions"
    $headers = @{
        Authorization = "Bearer $ApiKey"
        "Content-Type" = "application/json"
    }
    $body = @{
        model = $Model
        temperature = 0.3
        response_format = @{ type = "json_object" }
        messages = @(
            @{ role = "system"; content = $SystemPrompt }
            @{ role = "user"; content = $UserPrompt }
        )
    }

    $attempt = 1
    while ($true) {
        try {
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body (Json $body)
            $content = [string]$response.choices[0].message.content
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
    $targetTypes = @("clean", "paraphrase_service", "paraphrase_customer", "layout_spacing", "filler_light", "summary_short")
    $sanitized = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($variant in @($Variants)) {
        if ($index -ge $Count) { break }
        $augType = NWS ([string]$variant.aug_type)
        if (-not $augType) { $augType = $targetTypes[$index] }
        $answerStyle = NWS ([string]$variant.answer_style)
        if (-not $answerStyle) {
            $answerStyle = if ($augType -eq "summary_short") { "short" } else { "gold" }
        }
        $answerGold = if (NWS ([string]$variant.answer_gold)) { Normalize-Answer ([string]$variant.answer_gold) } elseif ($answerStyle -eq "short") { $BaseShort } else { $BaseGold }
        $answerStandardized = if (NWS ([string]$variant.answer_standardized)) { Normalize-Answer ([string]$variant.answer_standardized) } elseif ($answerStyle -eq "short") { $BaseShort } else { $BaseStandardized }
        $answerShort = if (NWS ([string]$variant.answer_short)) { Normalize-Answer ([string]$variant.answer_short) } else { $BaseShort }
        $sttText = if (NWS ([string]$variant.stt_text)) { Normalize-Stt ([string]$variant.stt_text) } else { $BaseStt }
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
            answer_style = if ($fallbackType -eq "summary_short") { "short" } else { "gold" }
            stt_text = $BaseStt
            answer_gold = if ($fallbackType -eq "summary_short") { $BaseShort } else { $BaseGold }
            answer_standardized = if ($fallbackType -eq "summary_short") { $BaseShort } else { $BaseStandardized }
            answer_short = $BaseShort
        })
    }

    return $sanitized.ToArray()
}

function Get-LlmAugmentation($Row, [int]$VariantCount) {
    $caseId = [string]$Row.케이스ID
    $cachePath = Get-CachePath -CaseId $caseId -ModelName $Model -VariantCount $VariantCount
    if (-not $DisableCache -and (Test-Path -LiteralPath $cachePath)) {
        return (ConvertFrom-Json -InputObject (Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8))
    }

    $systemPrompt = @"
당신은 한국어 STT 상담 데이터셋 생성기입니다.
반드시 JSON만 출력합니다.
사실 보존이 최우선입니다.
금액, 날짜, 건수, 기관명, 채널, 결과는 원문과 정답지 힌트를 기준으로 유지합니다.
마스킹 값은 **** 형태를 유지합니다.
출력 스키마:
{
  "intent_type": "string",
  "answer_gold": "string",
  "answer_standardized": "string",
  "answer_short": "string",
  "summary_structured": {
    "customer_intent": "string",
    "agent_action": "string",
    "result": "string",
    "short_text": "string",
    "standard_text": "string",
    "slot_summary": {
      "request_type": "string",
      "target_product": "string",
      "agent_action": "string",
      "result": "string"
    }
  },
  "keyword_slots": {
    "intent_type": "string",
    "request_type": "string",
    "contract_count": "string",
    "payment_amounts": ["string"],
    "date_values": ["string"],
    "institutions": ["string"],
    "channels": ["string"],
    "documents": ["string"],
    "actions": ["string"],
    "outcomes": ["string"],
    "product_names": ["string"],
    "keywords": ["string"]
  },
  "keyword_labels": [
    {
      "keyword": "string",
      "canonical": "string",
      "type": "intent|channel|entity|domain|outcome|raw",
      "source": "llm",
      "confidence": 0.0,
      "evidence_span": "string"
    }
  ],
  "utterance_labels": [
    {
      "utterance_id": 1,
      "speaker": "상담사|고객|미상",
      "label": "고객요청|상담사확인질문|본인인증|처리안내|결과통보|불만제기|감정표현|일반발화",
      "text": "string"
    }
  ],
  "variants": [
    {
      "aug_type": "clean|paraphrase_service|paraphrase_customer|layout_spacing|filler_light|summary_short",
      "answer_style": "gold|short",
      "stt_text": "string",
      "answer_gold": "string",
      "answer_standardized": "string",
      "answer_short": "string"
    }
  ]
}
variants는 반드시 순서대로 clean, paraphrase_service, paraphrase_customer, layout_spacing, filler_light 를 포함합니다.
clean은 원문 의미를 유지한 정제본입니다.
paraphrase_*는 의미 보존형 표현 변경입니다.
layout_spacing은 띄어쓰기/구두점 중심의 표면 변화입니다.
filler_light는 군더더기 표현을 소량 추가하되 사실은 바꾸지 않습니다.
summary_short는 요청되지 않으면 포함하지 않습니다.
"@

    $userPrompt = @"
케이스ID: $($Row.케이스ID)
생성 variant 수: $VariantCount

[원본 STT]
$($Row.STT전문)

[기존 LLM답변 힌트]
$($Row.LLM답변)

[사람 정답지]
$($Row.정답지)

[키워드 힌트]
$($Row.키워드)

요구사항:
1. 원문과 정답지를 기준으로 base 요약과 라벨을 생성합니다.
2. variants는 정확히 $VariantCount 개 생성합니다.
3. answer_gold, answer_standardized, answer_short도 variant별로 함께 바꿉니다.
4. 키워드/슬롯/요약은 학습 데이터용으로 간결하고 일관되게 작성합니다.
5. JSON 외 텍스트를 절대 포함하지 마세요.
"@

    $payload = Invoke-OpenAIJson -SystemPrompt $systemPrompt -UserPrompt $userPrompt
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


