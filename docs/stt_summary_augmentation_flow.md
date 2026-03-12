# stt_summary.csv ?곗씠??遺꾩꽍 諛?利앷컯 ?먮쫫 ?ㅺ퀎

## 1. ?곗씠??媛쒖슂

- 湲곗? ?낅젰 ?뚯씪: [`data/origin/stt_summary.csv`](../data/origin/stt_summary.csv)
- 珥?嫄댁닔: 169嫄?- 而щ읆 援ъ꽦:
  - `耳?댁뒪ID`
  - `STT?꾨Ц`
  - `LLM?듬?`
  - `?뺣떟吏`
  - `?ㅼ썙??

## 2. ?낅뜲?댄듃??紐⑺몴

?대쾲 ?뚯씠?꾨씪?몄? ?⑥닚 STT 臾몄옣 蹂?뺣낫???꾨옒 ?먮쫫??湲곗??쇰줈 ?ш뎄?깊븳??

1. STT ?뺤젣? ?붿옄 ?⑥쐞 蹂듭썝
2. 洹쒖튃 湲곕컲 intent ?꾨낫 ?앹꽦
3. canonical keyword labeling
4. 援ъ“??summary label ?앹꽦
5. validator 湲곕컲 confidence ?곗텧
6. Gold/Silver/Weak ?깃툒??7. ?섎? 蹂댁〈??STT/summary 利앷컯
8. ?숈뒿??split ?앹꽦
9. 踰꾩쟾蹂??곗씠?곗뀑 ?뺤옣
10. 踰꾩쟾蹂??곗텧臾?寃利?
## 3. ?듭떖 ?ㅺ퀎 ?먯튃

- `?뺣떟吏`? `?ㅼ썙??瑜??⑥닚 臾몄옄?댁씠 ?꾨땲??auto label??gold seed濡??ъ슜?쒕떎.
- ?쇰꺼媛믩쭔 ??ν븯吏 ?딄퀬 `method`, `confidence`, `validation` 寃곌낵瑜??④퍡 ??ν븳??
- `keyword`??raw 臾몄옄?댁씠 ?꾨땲??`canonical`, `type`, `evidence_span` 援ъ“濡???ν븳??
- `summary`??`customer_intent`, `agent_action`, `result` 援ъ“瑜?嫄곗퀜 ?먯뿰?대줈 蹂?섑븳??
- 利앷컯 ?곗씠?곕뒗 寃利앹쓣 ?듦낵???됰쭔 `Silver`濡??밴꺽?쒕떎.
- 紐⑤뱺 踰꾩쟾 ?곗텧臾쇱쓽 ?먮낯 ?낅젰? `stt_summary.csv` 1媛쒕쭔 ?좎??쒕떎.

## 4. ?꾩옱 援ы쁽 ?먮쫫

### 4-1. ?꾩쿂由?
- 怨듬갚 ?뺢퇋??- 諛섎났 filler 異뺤빟
- 留덉뒪???좏겙 `****` ?듭씪
- `?곷떞??` / `怨좉컼:` ?붿옄 ?뺤떇 ?듭씪

### 4-2. utterance labeling

- 諛쒗솕瑜?以??⑥쐞濡?遺꾨━
- `怨좉컼?붿껌`, `?곷떞?ы솗?몄쭏臾?, `蹂몄씤?몄쬆`, `泥섎━?덈궡`, `寃곌낵?듬낫`, `遺덈쭔?쒓린`, `媛먯젙?쒗쁽`, `?쇰컲諛쒗솕`濡?遺꾨쪟

### 4-3. auto labeling

- `intent_type` 異붾줎
- ?щ’ 異붿텧: 怨꾩빟嫄댁닔, 湲덉븸, ?좎쭨, 湲곌?, 梨꾨꼸, 臾몄꽌, ?됱쐞, 寃곌낵, ?곹뭹紐?- keyword labeling: `keyword`, `canonical`, `type`, `source`, `confidence`, `evidence_span`
- summary labeling: `customer_intent`, `agent_action`, `result`, `short_text`, `standard_text`
- quality tagging: `missing_slots`, `hallucination_risk`, `validation_pass`, `validation_reasons`

### 4-4. augmentation

- STT ?쒗쁽 蹂?? `paraphrase_service`, `paraphrase_customer`, `layout_spacing`, `filler_light`
- summary ?쒗쁽 蹂?? `summary_short`
- ?レ옄/?좎쭨/嫄댁닔 蹂댁〈 寃利?- confidence 0.8 ?댁긽?대ŉ validator ?듦낵 ??`Silver`

## 5. 理쒖쥌 ?곗텧臾?
?뺤젣/利앷컯 ?곗텧臾?

- [`data/processed/base_clean.csv`](../data/processed/base_clean.csv)
- [`data/processed/base_normalized.csv`](../data/processed/base_normalized.csv)
- [`data/processed/augmented_dataset.csv`](../data/processed/augmented_dataset.csv)
- [`data/processed/augmented_validated.csv`](../data/processed/augmented_validated.csv)

split ?곗텧臾?

- [`data/splits/base_train.csv`](../data/splits/base_train.csv)
- [`data/splits/base_valid.csv`](../data/splits/base_valid.csv)
- [`data/splits/base_test.csv`](../data/splits/base_test.csv)
- [`data/splits/train_augmented.csv`](../data/splits/train_augmented.csv)
- [`data/splits/train_final.csv`](../data/splits/train_final.csv)

踰꾩쟾 ?곗텧臾?

- [`data/versions/ver1.0`](../data/versions/ver1.0)
- [`data/versions/ver1.1`](../data/versions/ver1.1)
- [`data/versions/ver1.2`](../data/versions/ver1.2)




## 6. 二쇱슂 異붽? 而щ읆

- `label_grade`
- `label_confidence`
- `answer_short`
- `summary_structured`
- `keyword_labels`
- `utterance_labels`
- `auto_label_json`
- `validation_pass`
- `validation_reason`

## 7. ??以?寃곕줎

?꾩옱 ?뚯씠?꾨씪?몄? `?뺤젣 + canonical label + 援ъ“??summary + validator + ?깃툒??+ ?섎? 蹂댁〈??利앷컯 + 踰꾩쟾蹂??곗텧 ?뺣━` ?먮쫫?쇰줈 ?뺣━?섏뿀??
