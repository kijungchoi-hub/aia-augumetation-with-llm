# AIA STT Augmentation Pipeline

`data/origin/stt_summary.csv`를 입력으로 사용해 STT 정제, intent/slot 생성, answer 생성 및 증강, 학습용 split 생성, 버전별 데이터셋 생성, 검수페이지 자산 생성을 수행하는 PowerShell 기반 파이프라인입니다.

## 프로젝트 구성

- `scripts/Invoke-SttAugmentation.ps1`
  - 원본 CSV를 읽어 `base_clean.csv`, `base_normalized.csv`, `augmented_dataset.csv`, `augmented_validated.csv`를 생성합니다.
  - `stt_text`뿐 아니라 `answer_gold`, `answer_standardized`, `answer_short`도 함께 생성합니다.
  - 기본 증강 타입은 `clean`, `paraphrase_service`, `paraphrase_customer`, `answer_polite`, `answer_compact`입니다.
- `scripts/Split-SttDataset.ps1`
  - 처리 결과를 읽어 `train/valid/test` split을 생성합니다.
- `scripts/New-DatasetVersions.ps1`
  - `data/splits` 또는 기존 `ver1.0` 기준본을 기준으로 `ver1.0`부터 `ver1.5`까지 생성합니다.
- `scripts/Export-QualityReviewData.ps1`
  - 버전별 CSV를 검수페이지에서 사용하는 정적 JS 자산으로 변환합니다.
- `start-review.ps1`
  - Python `http.server`로 검수페이지를 로컬에서 실행합니다.
- `web/quality-review.html`
  - 버전별 데이터셋을 브라우저에서 검수하는 정적 페이지입니다.

## 입력과 출력 경로

- 원본 입력: `data/origin/stt_summary.csv`
- 처리 결과: `data/processed`
- split 결과: `data/splits`
- 버전별 데이터셋: `data/versions`
- 검수페이지 자산: `web/review-data`
- 백업: `data/archive`

## 처리 흐름

1. STT 전문 정제
2. intent / keyword slot / utterance label 생성
3. gold / standardized / short answer 생성
4. validator 기반 유효성 검사
5. STT 및 answer 증강 데이터 생성
6. 학습용 split 생성
7. 버전별 데이터셋 생성
8. 검수페이지 자산 생성

## 주요 컬럼

- `stt_text`
- `answer_gold`
- `answer_standardized`
- `answer_short`
- `intent_type`
- `label_grade`
- `label_confidence`
- `keyword_slots`
- `keyword_labels`
- `utterance_labels`
- `auto_label_json`
- `validation_pass`
- `validation_reason`

## 증강 타입

- `clean`
- `paraphrase_service`
- `paraphrase_customer`
- `answer_polite`
- `answer_compact`

`answer_polite`, `answer_compact`는 STT는 유지하고 answer 계열만 변형하는 answer-only 증강입니다.

## 실행 순서

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-SttAugmentation.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Split-SttDataset.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\New-DatasetVersions.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Export-QualityReviewData.ps1
```

## 주요 파라미터

### `scripts/Invoke-SttAugmentation.ps1`

- `-InputCsv`
- `-OutputDir`
- `-CacheDir`
- `-Model`
- `-CodexCommand`
- `-AugmentationsPerCase`
- `-MaxRows`
- `-RequestDelayMs`
- `-MaxRetries`
- `-CodexTimeoutSec`
- `-DisableCache`

기본 모델은 `gpt-5.4`이며 기본 증강 개수는 `5`입니다.

## 현재 데이터 건수

### processed 기준

- `base_clean=169`
- `base_normalized=169`
- `augmented_dataset=845`
- `augmented_validated=196`

### splits 기준

- `base_train=136`
- `base_valid=16`
- `base_test=17`
- `train_augmented=229`
- `train_final=365`

### versions 기준

- `ver1.0`: `train_augmented=229`, `train_final=365`
- `ver1.1`: `train_augmented=458`, `train_final=730`
- `ver1.2`: `train_augmented=916`, `train_final=1460`
- `ver1.3`: `train_augmented=1832`, `train_final=2920`
- `ver1.4`: `train_augmented=3664`, `train_final=5840`
- `ver1.5`: `train_augmented=7328`, `train_final=11680`

## 버전 규칙

- `ver1.0`: 증강 데이터 1배
- `ver1.1`: 증강 데이터 2배
- `ver1.2`: 증강 데이터 4배
- `ver1.3`: 증강 데이터 8배
- `ver1.4`: 증강 데이터 16배
- `ver1.5`: 증강 데이터 32배

## 검수페이지

- 페이지: `web/quality-review.html`
- 스타일: `web/quality-review.css`
- 스크립트: `web/quality-review.js`
- 생성 자산: `web/review-data`
- 생성 스크립트: `scripts/Export-QualityReviewData.ps1`

### 사용 방법

1. 검수 자산 생성

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Export-QualityReviewData.ps1
```

2. 로컬 서버 실행

```powershell
powershell -ExecutionPolicy Bypass -File .\start-review.ps1
```

3. 브라우저에서 `http://localhost:8000/web/quality-review.html` 열기

## 최근 백업

- `data/archive/augmentation_snapshots/20260313_171122`
  - answer 증강 반영 전후 산출물 백업
- `data/archive/augmentation_snapshots/20260316_094818`
  - 구버전 `data/versions` 및 `web/review-data` 재생성 전 백업

## 빠른 검증 명령

```powershell
Import-Csv .\data\processed\base_normalized.csv | Measure-Object
Import-Csv .\data\processed\augmented_validated.csv | Measure-Object
Import-Csv .\data\splits\train_final.csv | Measure-Object
Import-Csv .\data\versions\ver1.5\train_final.csv | Measure-Object
```

```powershell
rg -n "\[MASK\]" .\data .\docs .\scripts
rg -n "\*\*\*\*" .\data\splits .\data\versions
```

## 참고 문서

- `docs/stt_summary_augmentation_flow.md`
- `docs/keyword_slot_rules.md`
- `docs/stt_summary_augmentation_with_auto_labeling.md`
