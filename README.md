# AIA STT Augmentation Pipeline

`data/origin/stt_summary.csv`를 기준 입력으로 사용해 STT 정제, auto labeling, 요약/표현 증강, 학습용 split 생성, 버전별 데이터셋 확장을 수행한다.

## 프로젝트 구조

- `scripts/Invoke-SttAugmentation.ps1`
  - 원본 CSV를 읽어 정제본, 정규화본, 증강본, 검증 통과본을 생성한다.
- `scripts/Split-SttDataset.ps1`
  - 정규화/검증 결과를 읽어 `train/valid/test` split을 생성한다.
- `scripts/New-DatasetVersions.ps1`
  - `data/splits`를 기준으로 `ver1.0`, `ver1.1`, `ver1.2`를 생성한다.
- `docs/stt_summary_augmentation_flow.md`
  - 전체 증강 및 auto labeling 흐름 설명
- `docs/keyword_slot_rules.md`
  - keyword/slot 추출 및 검증 규칙 설명
- `docs/stt_summary_augmentation_with_auto_labeling.md`
  - 설계 기준 문서
- `scripts/dev/Run-AugmentationDebug.ps1`
  - augmentation 스크립트 단독 실행과 오류 확인용 디버그 진입점

## 디렉터리 정리 원칙

- 루트에는 실행 진입점과 핵심 문서만 둔다.
- 현재 파이프라인이 직접 사용하는 데이터는 `data/origin`, `data/processed`, `data/splits`, `data/versions`에 둔다.
- 과거 시트 기준 복사본이나 보관용 산출물은 `data/archive` 아래에 둔다.

## 기준 입력 파일

- canonical 원본: `data/origin/stt_summary.csv`
- 과거 원본명이나 임시 복사본은 유지하지 않는다.

## 처리 흐름

1. STT 전문 정제
2. 화자 단위 utterance 복원 및 utterance labeling
3. intent 추론과 keyword slot 추출
4. canonical keyword labeling 생성
5. 구조화 summary 생성
6. validator 기반 confidence 산출
7. Gold/Silver/Weak 등급화
8. 의미 보존형 STT/summary 증강
9. split 생성
10. 버전별 데이터셋 확장
11. 버전별 산출물 검증

## 산출물

### 전처리/증강

- `data/processed/base_clean.csv`
- `data/processed/base_normalized.csv`
- `data/processed/augmented_dataset.csv`
- `data/processed/augmented_validated.csv`

### split

- `data/splits/base_train.csv`
- `data/splits/base_valid.csv`
- `data/splits/base_test.csv`
- `data/splits/train_augmented.csv`
- `data/splits/train_final.csv`

### 버전 데이터셋

- `data/versions/ver1.0`
- `data/versions/ver1.1`
- `data/versions/ver1.2`

### 보관 데이터

- `data/archive/sheet_versions`
  - 시트 기준 원본/전처리/split 스냅샷 보관본

## 추가 컬럼 설명

### processed/augmented 계열 주요 컬럼

- `answer_style`
  - 요약 표현 유형. 예: `gold`, `short`
- `label_grade`
  - 라벨 신뢰 등급. 예: `Gold`, `Silver`, `Weak`
- `label_confidence`
  - 규칙/검증 기반 confidence score
- `answer_short`
  - 구조화 summary에서 생성한 짧은 요약
- `summary_structured`
  - `customer_intent`, `agent_action`, `result`, `slot_summary`를 담은 JSON 문자열
- `keyword_slots`
  - intent, 금액, 날짜, 기관, 채널, 문서, 결과 등을 구조화한 JSON 문자열
- `keyword_labels`
  - canonical keyword labeling 결과 JSON 문자열
- `utterance_labels`
  - 화자 단위 발화 라벨링 결과 JSON 문자열
- `auto_label_json`
  - summary/keyword/quality tag를 묶은 최종 auto labeling JSON 문자열
- `validation_pass`
  - validator 통과 여부
- `validation_reason`
  - 검증 결과 사유. 예: `ok`, `amount_mismatch`, `too_short`

### split 계열에서 유지되는 보조 컬럼

- `answer_style`
- `label_grade`
- `label_confidence`
- `answer_short`
- `keyword_slots`
- `keyword_labels`
- `utterance_labels`
- `auto_label_json`

## 컬럼 예시

### `summary_structured`

```json
{
  "customer_intent": "가상계좌 발송 또는 입금 가능 여부를 요청함",
  "agent_action": "가상계좌 발송 가능 여부와 금액을 안내함",
  "result": "문자 발송 기준으로 정리됨",
  "slot_summary": {
    "request_type": "가상계좌",
    "agent_action": "발송, 안내",
    "result": "가상계좌 발송"
  }
}
```

### `keyword_labels`

```json
[
  {
    "keyword": "가상계좌문자요청",
    "canonical": "가상계좌",
    "type": "intent",
    "source": "keyword+rule",
    "confidence": 0.88,
    "evidence_span": "가상계좌문자요청"
  }
]
```

### `utterance_labels`

```json
[
  {
    "utterance_id": 5,
    "speaker": "고객",
    "label": "고객요청",
    "text": "가상계좌 좀 보내주세요."
  },
  {
    "utterance_id": 17,
    "speaker": "상담사",
    "label": "처리안내",
    "text": "문자로 발송해 드리겠습니다."
  }
]
```

### `auto_label_json`

```json
{
  "call_id": "2",
  "auto_labels": {
    "summary_label": {
      "text": "가상계좌 발송 요청에 대해 발송 가능 여부와 금액을 안내하고 문자 발송으로 정리함",
      "short_text": "가상계좌 발송 요청, 문자 발송으로 정리됨",
      "method": "rule_structured_v2",
      "confidence": 0.98
    },
    "issue_type": {
      "label": "가상계좌",
      "confidence": 0.99
    },
    "quality_tags": {
      "missing_slots": [],
      "hallucination_risk": false,
      "validation_pass": true,
      "validation_reasons": []
    }
  }
}
```

## split 규칙

- `case_id % 10 == 0`: `test`
- `case_id % 10 == 1`: `valid`
- 나머지: `train`

증강 데이터는 `train` 케이스에만 합쳐 `train_final.csv`에 포함한다.

## 버전 규칙

- `ver1.0`: 현재 기준 데이터셋
- `ver1.1`: `train` 증강 배수를 2배로 확장한 데이터셋
- `ver1.2`: `train` 증강 배수를 4배로 확장한 데이터셋

## 데이터 품질검수 웹페이지

- 변환 스크립트: `scripts/Export-QualityReviewData.ps1`
- 검수 페이지: `web/quality-review.html`
- 생성 데이터 자산: `web/review-data`

### 사용 방법

1. `powershell -ExecutionPolicy Bypass -File .\scripts\Export-QualityReviewData.ps1`
2. 브라우저에서 `web/quality-review.html`을 연다.
3. 버전과 CSV 파일을 선택한 뒤 각 행에 대해 `Y` 또는 `N`으로 판정한다.
4. 필요하면 `현재 파일 결과 CSV` 또는 `전체 결과 CSV`로 내보낸다.

### 검수 결과 저장 방식

- 브라우저 `localStorage`에 임시 저장된다.
- 내보내기 CSV에는 `dataset_key`, `row_key`, `review_result`, `review_note`, `updated_at` 등이 포함된다.
- `ver1.1`: `train_augmented`, `train_final` 2배
- `ver1.2`: `train_augmented`, `train_final` 4배

현재 기준 건수:

- `base_train=136`
- `base_valid=16`
- `base_test=17`
- `train_augmented=645`
- `train_final=781`

버전별 건수:

- `ver1.0`: `train_augmented=645`, `train_final=781`
- `ver1.1`: `train_augmented=1290`, `train_final=1562`
- `ver1.2`: `train_augmented=2580`, `train_final=3124`

## 검증 규칙

- 금액 유지
- 날짜 유지
- 계약 건수 유지
- 마스킹 토큰 `****` 유지
- 지나치게 짧은 문장 제외
- validator 통과 + confidence 기준 충족 시 `Silver`

## 권장 실행 순서

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-SttAugmentation.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Split-SttDataset.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\New-DatasetVersions.ps1
```

## 검증 명령

생성 건수 확인:

```powershell
Import-Csv .\data\processed\base_normalized.csv | Measure-Object
Import-Csv .\data\processed\augmented_validated.csv | Measure-Object
Import-Csv .\data\splits\train_final.csv | Measure-Object
Import-Csv .\data\versions\ver1.2\train_final.csv | Measure-Object
```

마스킹 표기 확인:

```powershell
rg -n "\[MASK\]" .\data .\docs .\scripts
rg -n "\*\*\*\*" .\data\splits .\data\versions
```

샘플 행 확인:

```powershell
Import-Csv .\data\processed\base_normalized.csv | Select-Object -First 1 case_id,intent_type,label_grade,label_confidence,answer_short
Import-Csv .\data\splits\train_augmented.csv | Select-Object -First 1 sample_id,aug_type,stt_text,answer_gold
Import-Csv .\data\versions\ver1.1\manifest.csv
```
