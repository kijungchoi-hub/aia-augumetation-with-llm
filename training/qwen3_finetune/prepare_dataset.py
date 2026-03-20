from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any

DEFAULT_SYSTEM_PROMPT = (
    "당신은 보험사 고객센터 STT를 읽고 핵심 사실만 유지한 표준 요약 답변을 생성하는 어시스턴트다. "
    "금액, 날짜, 건수, 채널, 서류, 처리 결과를 정확히 유지하고 추측하지 않는다."
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare Qwen3 SFT datasets from pipeline CSV outputs.")
    parser.add_argument("--train-csv", required=True)
    parser.add_argument("--valid-csv", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--target-column", default="answer_standardized")
    parser.add_argument("--system-prompt", default=DEFAULT_SYSTEM_PROMPT)
    parser.add_argument("--include-intent", action="store_true")
    parser.add_argument("--include-keyword-slots", action="store_true")
    parser.add_argument("--include-answer-short-hint", action="store_true")
    parser.add_argument("--max-train-rows", type=int, default=0)
    parser.add_argument("--max-valid-rows", type=int, default=0)
    return parser.parse_args()


def read_rows(path: Path, limit: int = 0) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        rows = []
        for index, row in enumerate(reader, start=1):
            rows.append({key: (value or "") for key, value in row.items()})
            if limit > 0 and index >= limit:
                break
    return rows


def build_user_message(row: dict[str, str], args: argparse.Namespace) -> str:
    parts = [
        "다음 고객센터 STT를 읽고 표준 요약 답변을 작성하세요.",
        "[STT]",
        row.get("stt_text", "").strip(),
    ]

    intent = row.get("intent_type", "").strip()
    if args.include_intent and intent:
        parts.extend(["", "[Intent Hint]", intent])

    keyword_slots = row.get("keyword_slots", "").strip()
    if args.include_keyword_slots and keyword_slots:
        parts.extend(["", "[Keyword Slots]", keyword_slots])

    answer_short = row.get("answer_short", "").strip()
    if args.include_answer_short_hint and answer_short:
        parts.extend(["", "[Short Answer Hint]", answer_short])

    parts.extend([
        "",
        "출력 규칙:",
        "- 한국어 한 문단으로 작성합니다.",
        "- 사실만 유지하고 과장하거나 추측하지 않습니다.",
        "- 상담사의 안내/처리 결과가 있으면 반영합니다.",
    ])
    return "\n".join(parts).strip()


def build_record(row: dict[str, str], args: argparse.Namespace) -> dict[str, Any]:
    target = row.get(args.target_column, "").strip()
    if not target:
        raise ValueError(f"target column '{args.target_column}' is empty for sample_id={row.get('sample_id', '')}")

    return {
        "messages": [
            {"role": "system", "content": args.system_prompt},
            {"role": "user", "content": build_user_message(row, args)},
            {"role": "assistant", "content": target},
        ],
        "metadata": {
            "sample_id": row.get("sample_id", ""),
            "source_case_id": row.get("source_case_id", ""),
            "split": row.get("split", ""),
            "aug_type": row.get("aug_type", ""),
            "answer_style": row.get("answer_style", ""),
            "intent_type": row.get("intent_type", ""),
            "target_column": args.target_column,
        },
    }


def write_jsonl(path: Path, records: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")



def main() -> None:
    args = parse_args()
    train_csv = Path(args.train_csv)
    valid_csv = Path(args.valid_csv)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    train_rows = read_rows(train_csv, args.max_train_rows)
    valid_rows = read_rows(valid_csv, args.max_valid_rows)

    train_records = [build_record(row, args) for row in train_rows]
    valid_records = [build_record(row, args) for row in valid_rows]

    train_path = output_dir / "train.jsonl"
    valid_path = output_dir / "valid.jsonl"
    manifest_path = output_dir / "manifest.json"

    write_jsonl(train_path, train_records)
    write_jsonl(valid_path, valid_records)

    manifest = {
        "train_csv": str(train_csv),
        "valid_csv": str(valid_csv),
        "target_column": args.target_column,
        "train_rows": len(train_records),
        "valid_rows": len(valid_records),
        "system_prompt": args.system_prompt,
        "include_intent": args.include_intent,
        "include_keyword_slots": args.include_keyword_slots,
        "include_answer_short_hint": args.include_answer_short_hint,
        "output_files": {
            "train": str(train_path),
            "valid": str(valid_path),
        },
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"Prepared train dataset: {train_path} rows={len(train_records)}")
    print(f"Prepared valid dataset: {valid_path} rows={len(valid_records)}")
    print(f"Prepared manifest: {manifest_path}")


if __name__ == "__main__":
    main()
