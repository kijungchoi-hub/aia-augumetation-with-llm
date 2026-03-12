[CmdletBinding()]
param(
    [string]$InputCsv = ".\data\origin\stt_summary.csv",
    [string]$OutputDir = ".\data\processed",
    [int]$AugmentationsPerCase = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function NWS([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $t = $Text -replace "`r", "" -replace "[\t ]+", " " -replace "\n{3,}", "`n`n"
    return $t.Trim()
}

function Normalize-Stt([string]$Text) {
    $t = NWS $Text
    $t = $t -replace "\*{2,}", "****"
    $t = $t -replace "\b(네)( \1){1,}\b", '$1' -replace "\b(음)( \1){1,}\b", '$1' -replace "\b(그)( \1){1,}\b", '$1'
    $t = $t -replace "상담사\s*:", "상담사: " -replace "고객\s*:", "고객: " -replace ":\s{2,}", ": "
    return $t
}

function Normalize-Answer([string]$Text) {
    $t = (NWS $Text) -replace "\*{2,}", "****"
    return ($t -replace "\s+\.", "." -replace "\s+,", ",")
}

function Tokens([string]$KeywordText) {
    if ([string]::IsNullOrWhiteSpace($KeywordText)) { return @() }
    return @(($KeywordText -split "/|\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) | Select-Object -Unique)
}

function RegexValues([string]$Text, [string]$Pattern) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    return @([regex]::Matches($Text, $Pattern) | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
}

function Json($InputObject) { return ($InputObject | ConvertTo-Json -Depth 8 -Compress) }

function Infer-Intent([string[]]$KeywordTokens, [string]$AnswerText, [string]$SttText) {
    $joined = (($KeywordTokens + @($AnswerText, $SttText)) -join " ")
    $rules = @(
        @{ intent = "가상계좌"; pats = @("가상계좌", "당일입금", "입금가능") }
        @{ intent = "보험료납입"; pats = @("보험료", "월보험료", "납입", "납부", "자동이체", "출금예정") }
        @{ intent = "보험금청구"; pats = @("보험금", "청구", "진단금", "수술비") }
        @{ intent = "해지환급"; pats = @("해지", "해약", "환급", "해지환급금", "해약환급금") }
        @{ intent = "서류안내발송"; pats = @("서류", "팩스", "링크", "모바일링크", "문자발송", "발송요청") }
        @{ intent = "대출"; pats = @("대출", "상환") }
        @{ intent = "가입취소반송"; pats = @("청약", "철회", "반송", "취소요청") }
        @{ intent = "계약변경"; pats = @("주소변경", "카드변경", "계약자변경", "명의변경", "납입자", "자동이체변경") }
        @{ intent = "보장문의"; pats = @("보장문의", "보장내용", "보장금액", "암진단금", "고액암") }
    )
    $best = "기타"; $score = 0
    foreach ($rule in $rules) {
        $s = 0
        foreach ($pat in $rule.pats) { if ($joined -match [regex]::Escape($pat)) { $s++ } }
        if ($s -gt $score) { $best = $rule.intent; $score = $s }
    }
    return $best
}

function Utterances([string]$Text) {
    $list = New-Object System.Collections.Generic.List[object]
    $i = 1
    foreach ($line in ($Text -split "`n")) {
        $line = $line.Trim()
        if (-not $line) { continue }
        if ($line -match "^(상담사|고객)\s*:\s*(.+)$") {
            $speaker = $matches[1]; $body = $matches[2].Trim()
        } else {
            $speaker = if ($list.Count -gt 0) { $list[$list.Count - 1].speaker } else { "미상" }
            $body = $line
        }
        $label = "일반발화"
        if ($speaker -eq "고객" -and $body -match "요청|보내|바꿔|취소|문의|해지|청구|변경") { $label = "고객요청" }
        elseif ($speaker -eq "상담사" -and $body -match "맞으시|생년월일|몇 번|확인") { $label = "상담사확인질문" }
        elseif ($body -match "휴대폰 번호|생년월일|앞 6자리|4자리는") { $label = "본인인증" }
        elseif ($speaker -eq "상담사" -and $body -match "안내|발송|전달|처리|진행|접수|가능|불가") { $label = "처리안내" }
        elseif ($body -match "완료|입금되|정상적으로|없음") { $label = "결과통보" }
        elseif ($body -match "불만|왜|안 됐|안됐|거부") { $label = "불만제기" }
        elseif ($body -match "감사|수고|고맙") { $label = "감정표현" }
        $list.Add([pscustomobject]@{ utterance_id = $i; speaker = $speaker; label = $label; text = $body })
        $i++
    }
    return $list.ToArray()
}

function Keyword-Labels([string[]]$KeywordTokens, [string]$IntentType, [string]$Combined) {
    $catalog = @(
        @{ canonical = "가상계좌"; type = "intent"; pats = @("가상계좌", "당일입금", "입금가능") }
        @{ canonical = "보험료납입"; type = "intent"; pats = @("보험료", "월보험료", "납입", "납부", "자동이체") }
        @{ canonical = "보험금청구"; type = "intent"; pats = @("보험금청구", "보험금 청구", "청구") }
        @{ canonical = "해지환급"; type = "intent"; pats = @("해지", "해약", "환급") }
        @{ canonical = "계약변경"; type = "intent"; pats = @("주소변경", "카드변경", "계약자변경", "명의변경") }
        @{ canonical = "문자"; type = "channel"; pats = @("문자", "문자발송", "금액문자", "가상계좌문자") }
        @{ canonical = "팩스"; type = "channel"; pats = @("팩스") }
        @{ canonical = "링크"; type = "channel"; pats = @("링크", "모바일링크") }
        @{ canonical = "새마을금고"; type = "entity"; pats = @("새마을금고") }
        @{ canonical = "암"; type = "domain"; pats = @("암", "암보험", "암진단금") }
        @{ canonical = "고액암"; type = "domain"; pats = @("고액암") }
        @{ canonical = "완료"; type = "outcome"; pats = @("완료", "처리완료", "출금완료") }
        @{ canonical = "가능"; type = "outcome"; pats = @("가능", "입금가능", "당일입금가능") }
        @{ canonical = "불가"; type = "outcome"; pats = @("불가") }
    )
    $seen = @{}
    $labels = New-Object System.Collections.Generic.List[object]
    foreach ($token in $KeywordTokens) {
        $entry = $null
        foreach ($c in $catalog) {
            foreach ($pat in $c.pats) {
                if ($token -match [regex]::Escape($pat)) { $entry = $c; break }
            }
            if ($entry) { break }
        }
        if (-not $entry) {
            foreach ($c in $catalog) {
                foreach ($pat in $c.pats) {
                    if ($Combined -match [regex]::Escape($pat) -and $token -match [regex]::Escape($IntentType)) { $entry = $c; break }
                }
                if ($entry) { break }
            }
        }
        if (-not $entry) { $entry = @{ canonical = $token; type = "raw"; pats = @($token) } }
        $key = "$token|$($entry.canonical)|$($entry.type)"
        if ($seen.ContainsKey($key)) { continue }
        $evidence = if ($Combined -match [regex]::Escape($token)) { $token } else { ($entry.pats | Where-Object { $Combined -match [regex]::Escape($_) } | Select-Object -First 1) }
        $labels.Add([pscustomobject]@{
            keyword = $token
            canonical = $entry.canonical
            type = $entry.type
            source = if ($entry.type -eq "raw") { "keyword_raw" } else { "keyword+rule" }
            confidence = if ($entry.type -eq "raw") { 0.72 } elseif ($token -eq $entry.canonical) { 0.95 } else { 0.88 }
            evidence_span = $evidence
        })
        $seen[$key] = $true
    }
    if (-not ($labels | Where-Object { $_.canonical -eq $IntentType -and $_.type -eq 'intent' })) {
        $labels.Add([pscustomobject]@{ keyword = $IntentType; canonical = $IntentType; type = "intent"; source = "intent_rule"; confidence = 0.9; evidence_span = $IntentType })
    }
    return $labels.ToArray()
}

function Slots([string[]]$KeywordTokens, [string]$AnswerText, [string]$SttText, [string]$IntentType) {
    $combined = (($KeywordTokens + @($AnswerText, $SttText)) -join " ")
    return [ordered]@{
        intent_type = $IntentType
        request_type = $IntentType
        contract_count = ([regex]::Match($combined, "\d+\s*건")).Value
        payment_amounts = @(RegexValues $combined "\d[\d,]*\s*(만\s*\d+)?\s*원")
        date_values = @(RegexValues $combined "\d+\s*년\s*\d+\s*월\s*\d+\s*일|\d+\s*월\s*\d+\s*일|\d+\s*월|\d+\s*일")
        institutions = @(RegexValues $combined "새마을금고|롯데카드|국민|신한카드|하나은행|고객센터|부서" | Select-Object -Unique)
        channels = @(RegexValues $combined "문자|팩스|링크|모바일링크|콜백|전화|앱" | Select-Object -Unique)
        documents = @(RegexValues $combined "사업자등록증|재직증명서|진단서|청구서|신분증|서류|청약서류" | Select-Object -Unique)
        actions = @(RegexValues $combined "발송|안내|변경|취소|청구|해지|납부|전달|접수|출금|상환|반송|콜백|유지|조회" | Select-Object -Unique)
        outcomes = @(RegexValues $combined "완료|발송함|안내|전달|출금완료|진행|가능|불가|처리|없음|정상" | Select-Object -Unique)
        product_names = @(RegexValues $combined "암|고액암|치매|종신보험|100세 시대 보험|2대질병보험" | Select-Object -Unique)
        keywords = @($KeywordTokens)
    }
}

function Summary([string]$IntentType, [hashtable]$Slots, [string]$AnswerText) {
    $customer = switch ($IntentType) {
        "가상계좌" { "고객이 가상계좌 발송 또는 입금 가능 여부를 요청함" }
        "보험료납입" { "고객이 보험료 납입 계약, 금액 또는 납부 상태를 문의함" }
        "보험금청구" { "고객이 보험금 청구 또는 청구 취소를 요청함" }
        "해지환급" { "고객이 해지환급금 또는 해지 진행을 문의함" }
        "계약변경" { "고객이 계약 정보 변경을 요청함" }
        default { "고객이 상담 의도와 관련된 처리를 문의함" }
    }
    $agent = if ($Slots.actions.Count -gt 0) { "상담사가 " + (($Slots.actions | Select-Object -First 3) -join ", ") + " 중심으로 안내함" } else { "상담사가 상담 내용을 확인하고 안내함" }
    $result = if ($Slots.outcomes.Count -gt 0) { "처리 결과는 " + (($Slots.outcomes | Select-Object -First 3) -join ", ") + " 기준으로 정리됨" } else { "최종 상태는 미확인" }
    return [ordered]@{
        customer_intent = $customer
        agent_action = $agent
        result = $result
        short_text = (($customer -replace "고객이 ", "") + ". " + ($result -replace "처리 결과는 ", "")).Trim()
        standard_text = if ($AnswerText) { $AnswerText } else { "$customer. $agent. $result." }
        slot_summary = [ordered]@{
            request_type = $Slots.request_type
            target_product = ($Slots.product_names -join ", ")
            agent_action = ($Slots.actions -join ", ")
            result = ($Slots.outcomes -join ", ")
        }
    }
}

function Validate([string]$OriginalText, [string]$CandidateText, [hashtable]$Slots) {
    $reasons = New-Object System.Collections.Generic.List[string]
    foreach ($amount in $Slots.payment_amounts) { if ($amount -and $OriginalText -match [regex]::Escape($amount) -and $CandidateText -notmatch [regex]::Escape($amount)) { $reasons.Add("amount_mismatch") } }
    if ($Slots.contract_count -and $OriginalText -match [regex]::Escape($Slots.contract_count) -and $CandidateText -notmatch [regex]::Escape($Slots.contract_count)) { $reasons.Add("contract_count_mismatch") }
    foreach ($dateValue in $Slots.date_values) { if ($dateValue -and $OriginalText -match [regex]::Escape($dateValue) -and $CandidateText -notmatch [regex]::Escape($dateValue)) { $reasons.Add("date_mismatch") } }
    if ($CandidateText -match "\[MASK\]") { $reasons.Add("mask_not_normalized") }
    if ($CandidateText.Length -lt 20) { $reasons.Add("too_short") }
    $hallucination = ($CandidateText -match "완료") -and ($OriginalText -notmatch "완료|발송|처리|입금")
    return @{ pass = ($reasons.Count -eq 0); reasons = @($reasons); hallucination_risk = $hallucination }
}

function Confidence([hashtable]$Slots, [object[]]$KeywordLabels, [hashtable]$Validation) {
    $s = 0.58
    if ($Slots.contract_count) { $s += 0.06 }
    if ($Slots.payment_amounts.Count -gt 0) { $s += 0.08 }
    if ($Slots.date_values.Count -gt 0) { $s += 0.05 }
    if ($Slots.actions.Count -gt 0) { $s += 0.06 }
    if ($Slots.outcomes.Count -gt 0) { $s += 0.05 }
    if ($KeywordLabels.Count -ge 3) { $s += 0.06 }
    if ($Validation.pass) { $s += 0.07 } else { $s -= 0.12 }
    if ($Validation.hallucination_risk) { $s -= 0.08 }
    return [math]::Round(([math]::Max([math]::Min($s, 0.98), 0.35)), 2)
}

function Grade([string]$RowType, [double]$Confidence, [bool]$ValidationPass) {
    if ($RowType -eq "base") { return "Gold" }
    if ($ValidationPass -and $Confidence -ge 0.8) { return "Silver" }
    return "Weak"
}

function AutoLabels([string]$CaseId, [hashtable]$Summary, [object[]]$KeywordLabels, [string]$IntentType, [hashtable]$Validation, [double]$Confidence) {
    return [ordered]@{
        call_id = $CaseId
        auto_labels = [ordered]@{
            summary_label = [ordered]@{ text = $Summary.standard_text; short_text = $Summary.short_text; method = "rule_structured_v2"; confidence = $Confidence }
            keyword_labels = @($KeywordLabels)
            issue_type = [ordered]@{ label = $IntentType; confidence = [math]::Round(([math]::Min($Confidence + 0.03, 0.99)), 2) }
            quality_tags = [ordered]@{
                missing_slots = @($Validation.reasons | Where-Object { $_ -match "mismatch" })
                hallucination_risk = $Validation.hallucination_risk
                validation_pass = $Validation.pass
                validation_reasons = @($Validation.reasons)
            }
        }
    }
}

function Replace-First([string]$Text, [object[]]$Pairs) {
    $result = $Text
    foreach ($pair in $Pairs) { $result = [regex]::Replace($result, [regex]::Escape($pair.From), $pair.To, 1) }
    return $result
}

function Variants([string]$SttText, [string]$AnswerText, [string]$ShortAnswer, [hashtable]$Slots, [int]$Count) {
    $candidates = @(
        [pscustomobject]@{ aug_type = "clean"; stt_text = $SttText; answer_text = $AnswerText; answer_style = "gold" }
        [pscustomobject]@{ aug_type = "paraphrase_service"; stt_text = (Replace-First $SttText @(@{ From = "안내"; To = "설명" }, @{ From = "발송"; To = "전송" }, @{ From = "문의"; To = "확인 요청" })); answer_text = $AnswerText; answer_style = "gold" }
        [pscustomobject]@{ aug_type = "paraphrase_customer"; stt_text = (Replace-First $SttText @(@{ From = "보내주세요"; To = "문자 부탁드려요" }, @{ From = "안 됐는데요"; To = "수신이 안 됐어요" }, @{ From = "부탁"; To = "요청" })); answer_text = $AnswerText; answer_style = "gold" }
        [pscustomobject]@{ aug_type = "layout_spacing"; stt_text = ($SttText -replace "고객:", "고객 :" -replace "상담사:", "상담사 :"); answer_text = $AnswerText; answer_style = "gold" }
        [pscustomobject]@{ aug_type = "filler_light"; stt_text = (($SttText -replace "고객: ", "고객: 음 ") -replace "상담사: ", "상담사: 네 "); answer_text = $AnswerText; answer_style = "gold" }
        [pscustomobject]@{ aug_type = "summary_short"; stt_text = $SttText; answer_text = $ShortAnswer; answer_style = "short" }
    )
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in ($candidates | Select-Object -First $Count)) {
        $stt = Normalize-Stt $candidate.stt_text
        $validation = Validate $SttText $stt $Slots
        $list.Add([pscustomobject]@{
            aug_type = $candidate.aug_type
            answer_style = $candidate.answer_style
            stt_text = $stt
            answer_gold = $candidate.answer_text
            validation_pass = $validation.pass
            validation_reason = if ($validation.reasons.Count -gt 0) { ($validation.reasons -join "|") } else { "ok" }
            hallucination_risk = $validation.hallucination_risk
        })
    }
    return $list.ToArray()
}

if (-not (Test-Path -LiteralPath $InputCsv)) { throw "Input CSV not found: $InputCsv" }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$rows = Import-Csv -Path $InputCsv
$baseClean = New-Object System.Collections.Generic.List[object]
$baseNormalized = New-Object System.Collections.Generic.List[object]
$augmented = New-Object System.Collections.Generic.List[object]

foreach ($row in $rows) {
    $caseId = [string]$row.케이스ID
    $stt = Normalize-Stt $row.STT전문
    $llm = Normalize-Answer $row.LLM답변
    $answer = Normalize-Answer $row.정답지
    $keywordTokens = Tokens $row.키워드
    $intent = Infer-Intent $keywordTokens $answer $stt
    $utteranceLabels = Utterances $stt
    $slots = Slots $keywordTokens $answer $stt $intent
    $summary = Summary $intent $slots $answer
    $combined = (($keywordTokens + @($answer, $stt)) -join " ")
    $keywordLabels = Keyword-Labels $keywordTokens $intent $combined
    $validation = Validate $stt $stt $slots
    $confidence = Confidence $slots $keywordLabels $validation
    $grade = Grade "base" $confidence $validation.pass
    $slotJson = Json $slots
    $summaryJson = Json $summary
    $keywordJson = Json $keywordLabels
    $utteranceJson = Json $utteranceLabels
    $autoJson = Json (AutoLabels $caseId $summary $keywordLabels $intent $validation $confidence)

    $baseClean.Add([pscustomobject]@{ case_id = $caseId; stt_text = $stt; llm_answer = $llm; answer_gold = $answer; keyword_raw = $row.키워드; utterance_count = $utteranceLabels.Count })
    $baseNormalized.Add([pscustomobject]@{
        case_id = $caseId; intent_type = $intent; label_grade = $grade; label_confidence = $confidence
        stt_text = $stt; llm_answer = $llm; answer_gold = $answer; answer_standardized = $summary.standard_text; answer_short = $summary.short_text
        summary_structured = $summaryJson; keyword_raw = $row.키워드; keyword_tokens = ($keywordTokens -join " | "); keyword_slots = $slotJson
        keyword_labels = $keywordJson; utterance_labels = $utteranceJson; auto_label_json = $autoJson
        validation_pass = $validation.pass; validation_reason = if ($validation.reasons.Count -gt 0) { ($validation.reasons -join "|") } else { "ok" }
    })

    $index = 1
    foreach ($variant in (Variants $stt $answer $summary.short_text $slots $AugmentationsPerCase)) {
        $augValidation = @{ pass = [bool]$variant.validation_pass; reasons = if ($variant.validation_reason -eq "ok") { @() } else { @($variant.validation_reason -split "\|") }; hallucination_risk = [bool]$variant.hallucination_risk }
        $augConfidence = Confidence $slots $keywordLabels $augValidation
        $augGrade = Grade "augmented" $augConfidence $variant.validation_pass
        $augSummary = Summary $intent $slots $variant.answer_gold
        $augmented.Add([pscustomobject]@{
            source_case_id = $caseId; aug_id = ("{0}-{1:D2}" -f $caseId, $index); aug_type = $variant.aug_type; answer_style = $variant.answer_style
            intent_type = $intent; label_grade = $augGrade; label_confidence = $augConfidence
            stt_text = $variant.stt_text; answer_gold = $variant.answer_gold; answer_standardized = $summary.standard_text; answer_short = $summary.short_text
            keyword_raw = $row.키워드; keyword_slots = $slotJson; keyword_labels = $keywordJson; utterance_labels = $utteranceJson
            auto_label_json = (Json (AutoLabels $caseId $augSummary $keywordLabels $intent $augValidation $augConfidence))
            validation_pass = $variant.validation_pass; validation_reason = $variant.validation_reason
        })
        $index++
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






