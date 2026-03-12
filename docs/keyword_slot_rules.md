# 키워드 슬롯화 규칙

## 목적

[`data/origin/stt_summary.csv`](../data/origin/stt_summary.csv)의 `키워드`, `정답지`, `STT전문`을 구조화해서 auto labeling, 증강 검증, 학습 입력으로 재사용하기 위한 규칙이다.

## 입력 기준

- 원본 컬럼: `키워드`
- 보조 컬럼: `정답지`, `STT전문`
- 분해 규칙:
  - `/` 기준 분리
  - 줄바꿈 기준 분리
  - trim 처리 후 빈 토큰 제거

## 표준 슬롯

| 슬롯명 | 설명 | 예시 |
|---|---|---|
| `intent_type` | 상담 의도 분류 | `가상계좌`, `보험료납입`, `보험금청구`, `보장문의` |
| `request_type` | 요약용 요청 타입 | `계약변경`, `서류안내발송` |
| `contract_count` | 계약 건수 | `1건`, `2건`, `3건` |
| `payment_amounts` | 금액 정보 | `32560원`, `19만 9760원`, `200만3150원` |
| `date_values` | 날짜/월/일 정보 | `9월 2일`, `25일`, `8월` |
| `institutions` | 은행/카드사/기관명 | `새마을금고`, `하나은행`, `롯데카드` |
| `channels` | 처리 채널 | `문자`, `팩스`, `링크`, `모바일링크`, `콜백`, `전화` |
| `documents` | 서류명 | `진단서`, `청구서`, `사업자등록증`, `신분증` |
| `actions` | 처리 행위 | `발송`, `안내`, `변경`, `취소`, `청구`, `전달` |
| `outcomes` | 처리 결과 | `완료`, `가능`, `불가`, `출금완료`, `진행` |
| `product_names` | 상품/보장 관련 명칭 | `암`, `고액암`, `치매` |
| `keywords` | 원본 분해 토큰 목록 | 원문 키워드 배열 |

## keyword label 구조

`keyword`는 단순 배열이 아니라 아래 구조로 저장한다.

```json
[
  {
    "keyword": "가상계좌문자",
    "canonical": "문자",
    "type": "channel",
    "source": "keyword+rule",
    "confidence": 0.9,
    "evidence_span": "문자"
  }
]
```

## 의도 분류 방식

현재 스크립트는 [`scripts/Invoke-SttAugmentation.ps1`](../scripts/Invoke-SttAugmentation.ps1)에서 규칙 기반 점수 방식으로 intent를 추론한다.

- `가상계좌`: `가상계좌`, `당일입금`, `입금가능`
- `보험료납입`: `보험료`, `월보험료`, `납입`, `납부`, `자동이체`, `출금예정`
- `보험금청구`: `보험금`, `청구`, `진단금`, `수술비`
- `해지환급`: `해지`, `해약`, `환급`, `해지환급금`, `해약환급금`
- `서류안내발송`: `서류`, `팩스`, `링크`, `모바일링크`, `문자발송`, `발송요청`
- `대출`: `대출`, `상환`
- `가입취소반송`: `청약`, `철회`, `반송`, `취소요청`
- `계약변경`: `주소변경`, `카드변경`, `계약자변경`, `명의변경`, `납입자`, `자동이체변경`
- `보장문의`: `보장문의`, `보장내용`, `보장금액`, `암진단금`, `고액암`
- 그 외: `기타`

## 검증 규칙

- 원래 STT에 존재한 금액은 증강 후에도 유지되어야 함
- 원래 STT에 존재한 날짜는 증강 후에도 유지되어야 함
- 원래 STT에 존재한 계약 건수는 증강 후에도 유지되어야 함
- 마스킹 토큰은 `****` 형식을 유지해야 함
- 지나치게 짧은 문장은 제외함
- validation 통과 + confidence 0.8 이상인 행만 `Silver`

## 출력 사용처

- [`data/processed/base_normalized.csv`](../data/processed/base_normalized.csv)
- [`data/processed/augmented_dataset.csv`](../data/processed/augmented_dataset.csv)
- [`data/processed/augmented_validated.csv`](../data/processed/augmented_validated.csv)
- 학습 입력: `stt_text`
- 학습 타깃: `answer_gold`
- 보조 피처: `intent_type`, `keyword_slots`, `keyword_labels`, `utterance_labels`, `auto_label_json`

