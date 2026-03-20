# Qwen3 파인튜닝

## 개요

이 저장소의 `train_final.csv`, `base_valid.csv`를 Qwen3 SFT 형식의 `chat jsonl`로 변환하고, Hugging Face `transformers` + `trl` + `peft` 기반으로 파인튜닝하는 절차입니다.

기본 목적은 `stt_text -> answer_standardized` 생성 학습입니다.

## 추가된 파일

- `training/qwen3_finetune/prepare_dataset.py`
- `training/qwen3_finetune/train.py`
- `training/requirements-qwen3.txt`
- `scripts/Export-Qwen3SftDataset.ps1`
- `scripts/Start-Qwen3FineTune.ps1`

## 1. 의존성 설치

```powershell
pip install -r .\training\requirements-qwen3.txt
```

CUDA 환경이 없거나 `bitsandbytes`를 쓰지 않을 경우 `--load-in-4bit`는 빼고 실행합니다.

## 2. 학습 데이터셋 생성

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Export-Qwen3SftDataset.ps1 -IncludeIntent -IncludeKeywordSlots
```

기본 입력:

- `data/versions/ver1.5/train_final.csv`
- `data/versions/ver1.5/base_valid.csv`

기본 출력:

- `data/finetune/qwen3/sft/train.jsonl`
- `data/finetune/qwen3/sft/valid.jsonl`
- `data/finetune/qwen3/sft/manifest.json`

## 3. Qwen3 파인튜닝 실행

### LoRA

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Start-Qwen3FineTune.ps1 -ModelNameOrPath 'Qwen/Qwen3-4B-Instruct' -TuningMode lora -LoadIn4bit -Bf16
```

### Full Fine-tuning

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Start-Qwen3FineTune.ps1 -ModelNameOrPath 'Qwen/Qwen3-4B-Instruct' -TuningMode full -Bf16
```

## 주요 파라미터

### Export-Qwen3SftDataset.ps1

- `-TargetColumn`
- `-IncludeIntent`
- `-IncludeKeywordSlots`
- `-IncludeAnswerShortHint`
- `-MaxTrainRows`
- `-MaxValidRows`

### Start-Qwen3FineTune.ps1

- `-ModelNameOrPath`
- `-TuningMode`
- `-MaxSeqLength`
- `-PerDeviceTrainBatchSize`
- `-GradientAccumulationSteps`
- `-LearningRate`
- `-NumTrainEpochs`
- `-LoadIn4bit`
- `-Bf16`
- `-Fp16`

## 출력물

기본 출력 디렉터리:

- `data/finetune/qwen3/outputs/qwen3-sft`

학습 결과:

- adapter 또는 full model weight
- tokenizer 파일
- `train_metrics.json`

## 주의사항

- 기본값은 `answer_standardized`를 정답으로 사용합니다.
- 원문 `stt_text`를 그대로 사용하므로 학습 데이터 접근 통제는 별도로 관리해야 합니다.
- `Qwen/Qwen3-4B-Instruct`는 예시이며, 실제 사용 모델 크기에 따라 VRAM 요구량이 크게 달라집니다.
