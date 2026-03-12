(function () {
  const storageKey = "quality-review-results-v1";
  const speakerAgent = "\uC0C1\uB2F4\uC0AC";
  const speakerCustomer = "\uACE0\uAC1D";
  const diffFieldNames = new Set(["answer_gold", "answer_standardized", "answer_short"]);
  const state = {
    index: window.QUALITY_REVIEW_INDEX || { datasets: [] },
    datasetsByKey: new Map(),
    loadedDatasets: new Map(),
    filteredRows: [],
    selectedVersion: "",
    selectedDatasetKey: "",
    selectedRowIndex: 0,
    results: loadResults(),
    originRowsByDataset: new Map(),
  };

  const preferredFieldOrder = [
    "sample_id",
    "source_case_id",
    "split",
    "aug_type",
    "answer_style",
    "intent_type",
    "label_grade",
    "label_confidence",
    "stt_text",
    "answer_gold",
    "answer_standardized",
    "answer_short",
    "keyword_raw",
    "keyword_slots",
    "keyword_labels",
    "utterance_labels",
    "auto_label_json",
  ];

  const compactFieldNames = new Set(preferredFieldOrder.slice(0, 8));

  const dom = {
    versionSelect: document.getElementById("versionSelect"),
    datasetSelect: document.getElementById("datasetSelect"),
    searchInput: document.getElementById("searchInput"),
    totalCount: document.getElementById("totalCount"),
    reviewedCount: document.getElementById("reviewedCount"),
    yesCount: document.getElementById("yesCount"),
    noCount: document.getElementById("noCount"),
    filterCount: document.getElementById("filterCount"),
    rowList: document.getElementById("rowList"),
    datasetTitle: document.getElementById("datasetTitle"),
    datasetMeta: document.getElementById("datasetMeta"),
    prevButton: document.getElementById("prevButton"),
    nextButton: document.getElementById("nextButton"),
    exportCurrentButton: document.getElementById("exportCurrentButton"),
    exportAllButton: document.getElementById("exportAllButton"),
    recordTitle: document.getElementById("recordTitle"),
    recordMeta: document.getElementById("recordMeta"),
    markYesButton: document.getElementById("markYesButton"),
    markNoButton: document.getElementById("markNoButton"),
    decisionBadge: document.getElementById("decisionBadge"),
    noteInput: document.getElementById("noteInput"),
    fieldGrid: document.getElementById("fieldGrid"),
  };

  init();

  function init() {
    state.index.datasets.forEach((dataset) => state.datasetsByKey.set(dataset.key, dataset));

    const versions = [...new Set(state.index.datasets.map((dataset) => dataset.version))];
    dom.versionSelect.innerHTML = versions
      .map((version) => `<option value="${escapeHtml(version)}">${escapeHtml(version)}</option>`)
      .join("");

    state.selectedVersion = versions[0] || "";
    dom.versionSelect.value = state.selectedVersion;

    dom.versionSelect.addEventListener("change", onVersionChange);
    dom.datasetSelect.addEventListener("change", onDatasetChange);
    dom.searchInput.addEventListener("input", renderRowList);
    dom.prevButton.addEventListener("click", () => moveSelection(-1));
    dom.nextButton.addEventListener("click", () => moveSelection(1));
    dom.markYesButton.addEventListener("click", () => markDecision("Y"));
    dom.markNoButton.addEventListener("click", () => markDecision("N"));
    dom.noteInput.addEventListener("input", onNoteChange);
    dom.exportCurrentButton.addEventListener("click", exportCurrentDataset);
    dom.exportAllButton.addEventListener("click", exportAllDatasets);

    populateDatasetSelect();
  }

  function onVersionChange() {
    state.selectedVersion = dom.versionSelect.value;
    populateDatasetSelect();
  }

  function populateDatasetSelect() {
    const datasets = state.index.datasets.filter((dataset) => dataset.version === state.selectedVersion);
    dom.datasetSelect.innerHTML = datasets
      .map((dataset) => `<option value="${escapeHtml(dataset.key)}">${escapeHtml(dataset.fileName)}</option>`)
      .join("");

    state.selectedDatasetKey = datasets[0] ? datasets[0].key : "";
    dom.datasetSelect.value = state.selectedDatasetKey;
    loadSelectedDataset();
  }

  function onDatasetChange() {
    state.selectedDatasetKey = dom.datasetSelect.value;
    loadSelectedDataset();
  }

  function loadSelectedDataset() {
    const datasetMeta = state.datasetsByKey.get(state.selectedDatasetKey);
    if (!datasetMeta) {
      renderEmpty("Dataset not found.");
      return;
    }

    loadDatasetScript(datasetMeta)
      .then(() => {
        state.selectedRowIndex = 0;
        renderDataset();
      })
      .catch((error) => {
        renderEmpty(`Failed to load dataset: ${error.message}`);
      });
  }

  function loadDatasetScript(datasetMeta) {
    if (state.loadedDatasets.has(datasetMeta.key)) {
      return Promise.resolve(state.loadedDatasets.get(datasetMeta.key));
    }

    if (window.QUALITY_REVIEW_DATA && window.QUALITY_REVIEW_DATA[datasetMeta.key]) {
      const dataset = window.QUALITY_REVIEW_DATA[datasetMeta.key];
      state.loadedDatasets.set(datasetMeta.key, dataset);
      return Promise.resolve(dataset);
    }

    return new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.charset = "utf-8";
      script.src = `./review-data/${datasetMeta.assetFile}`;
      script.onload = () => {
        const dataset = window.QUALITY_REVIEW_DATA && window.QUALITY_REVIEW_DATA[datasetMeta.key];
        if (!dataset) {
          reject(new Error("script loaded but dataset is missing"));
          return;
        }
        state.loadedDatasets.set(datasetMeta.key, dataset);
        resolve(dataset);
      };
      script.onerror = () => reject(new Error(datasetMeta.assetFile));
      document.body.appendChild(script);
    });
  }

  function renderDataset() {
    const dataset = state.loadedDatasets.get(state.selectedDatasetKey);
    if (!dataset) {
      renderEmpty("Dataset is not loaded yet.");
      return;
    }

    dom.datasetTitle.textContent = `${dataset.version} / ${dataset.fileName}`;
    dom.datasetMeta.textContent = `${dataset.rowCount} rows, ${dataset.columns.length} columns`;
    renderRowList();
    renderSummary();
    renderRecord();
  }

  function renderRowList() {
    const dataset = state.loadedDatasets.get(state.selectedDatasetKey);
    if (!dataset) {
      return;
    }

    const query = dom.searchInput.value.trim().toLowerCase();
    state.filteredRows = dataset.rows.filter((row) => matchesQuery(row, query));
    dom.filterCount.textContent = `${state.filteredRows.length} items`;

    if (!state.filteredRows.length) {
      state.selectedRowIndex = 0;
      dom.rowList.innerHTML = '<div class="empty-state">No matching rows found.</div>';
      renderRecord();
      renderSummary();
      return;
    }

    if (state.selectedRowIndex >= state.filteredRows.length) {
      state.selectedRowIndex = 0;
    }

    dom.rowList.innerHTML = state.filteredRows
      .map((row, index) => {
        const rowKey = getRowKey(dataset, row);
        const result = getDecision(dataset.key, rowKey);
        const values = row.values;
        const title = values.sample_id || values.source_case_id || `Row ${row.rowIndex}`;
        const meta = [values.split, values.intent_type, values.answer_style].filter(Boolean).join(" / ");
        const preview = shorten(
          values.answer_short || values.answer_standardized || values.answer_gold || values.stt_text || "",
          88
        );
        const activeClass = index === state.selectedRowIndex ? " active" : "";
        return `
          <button class="row-item${activeClass}" data-index="${index}" type="button">
            <p class="row-item-title">${escapeHtml(title)} <span class="muted">[${result || "-"}]</span></p>
            <p class="row-item-meta">${escapeHtml(meta || `row ${row.rowIndex}`)}</p>
            <p class="row-item-preview">${escapeHtml(preview)}</p>
          </button>
        `;
      })
      .join("");

    dom.rowList.querySelectorAll(".row-item").forEach((button) => {
      button.addEventListener("click", () => {
        state.selectedRowIndex = Number(button.dataset.index);
        renderRowList();
        renderRecord();
      });
    });

    renderSummary();
    renderRecord();
  }

  function renderSummary() {
    const dataset = state.loadedDatasets.get(state.selectedDatasetKey);
    if (!dataset) {
      return;
    }

    const decisions = Object.values(state.results[dataset.key] || {});
    const reviewed = decisions.filter((entry) => entry && entry.result).length;
    const yesCount = decisions.filter((entry) => entry && entry.result === "Y").length;
    const noCount = decisions.filter((entry) => entry && entry.result === "N").length;

    dom.totalCount.textContent = String(dataset.rowCount);
    dom.reviewedCount.textContent = String(reviewed);
    dom.yesCount.textContent = String(yesCount);
    dom.noCount.textContent = String(noCount);
  }

  function renderRecord() {
    const dataset = state.loadedDatasets.get(state.selectedDatasetKey);
    const row = state.filteredRows[state.selectedRowIndex];

    if (!dataset || !row) {
      dom.recordTitle.textContent = "Select a row to review.";
      dom.recordMeta.textContent = "";
      dom.decisionBadge.textContent = "Pending";
      dom.decisionBadge.className = "decision-badge";
      dom.noteInput.value = "";
      dom.fieldGrid.innerHTML = '<div class="empty-state">No record selected.</div>';
      return;
    }

    const rowKey = getRowKey(dataset, row);
    const decision = getDecision(dataset.key, rowKey);
    const note = getNote(dataset.key, rowKey);

    dom.recordTitle.textContent = row.values.sample_id || row.values.source_case_id || `Row ${row.rowIndex}`;
    dom.recordMeta.textContent = `row ${row.rowIndex} / ${dataset.rowCount}`;
    dom.decisionBadge.textContent = decision || "Pending";
    dom.decisionBadge.className = `decision-badge${decision === "Y" ? " yes" : decision === "N" ? " no" : ""}`;
    dom.noteInput.value = note;

    const fields = buildFieldEntries(dataset.columns, row.values);
    dom.fieldGrid.innerHTML = fields
      .map((field) => {
        const fullClass = field.value.length > 240 || field.name === "stt_text" ? " full" : "";
        return renderFieldCard(field, fullClass, row, dataset);
      })
      .join("");
  }

  function buildFieldEntries(columns, values) {
    const orderedNames = [
      ...preferredFieldOrder.filter((name) => columns.includes(name)),
      ...columns.filter((name) => !preferredFieldOrder.includes(name)),
    ];

    return orderedNames.map((name) => ({
      name,
      value: values[name] == null || values[name] === "" ? "-" : String(values[name]),
      compact: compactFieldNames.has(name),
    }));
  }

  function renderFieldCard(field, fullClass, row, dataset) {
    const parsed = parseStructuredValue(field.value);
    const originValues = getOriginValues(dataset, row);
    let body = `<pre class="field-value">${escapeHtml(field.value)}</pre>`;

    if (field.name === "stt_text") {
      body = renderSttText(field.value, originValues.stt_text || row.originSttText || "");
    } else if (diffFieldNames.has(field.name)) {
      body = renderTextDiffValue(field.value, originValues[field.name] || "");
    } else if (parsed) {
      body = renderStructuredValue(parsed, field.name);
    }

    const compactClass = field.compact ? " compact" : "";
    const sttClass = field.name === "stt_text" ? " stt-card" : "";

    return `
      <section class="field-card${compactClass}${sttClass}${fullClass}">
        <span class="field-name">${escapeHtml(field.name)}</span>
        ${body}
      </section>
    `;
  }

  function getOriginValues(dataset, row) {
    if (!dataset || !row) {
      return {};
    }

    if (!state.originRowsByDataset.has(dataset.key)) {
      const originMap = new Map();
      dataset.rows.forEach((item) => {
        const sourceCaseId = item.values.source_case_id || item.values.sample_id || "";
        const augType = String(item.values.aug_type || "").toLowerCase();
        if (sourceCaseId && augType === "original" && !originMap.has(sourceCaseId)) {
          originMap.set(sourceCaseId, item.values);
        }
      });
      state.originRowsByDataset.set(dataset.key, originMap);
    }

    const rowKey = row.values.source_case_id || row.values.sample_id || "";
    const originMap = state.originRowsByDataset.get(dataset.key);
    return originMap.get(rowKey) || {};
  }

  function renderTextDiffValue(value, originValue) {
    if (!value || value === "-") {
      return '<pre class="field-value">-</pre>';
    }

    const content = originValue ? renderTokenDiffText(value, originValue) : escapeHtml(value);
    return `<div class="text-diff-view">${content}</div>`;
  }

  function renderSttText(value, originValue) {
    const lines = formatSttLines(value);
    const originLines = formatSttLines(originValue);
    const hasOrigin = originLines.length > 0;

    if (!lines.length) {
      return '<div class="stt-view empty">-</div>';
    }

    const legend = hasOrigin
      ? `
        <div class="stt-diff-legend">
          <span class="stt-diff-chip added">Added</span>
        </div>
      `
      : "";

    return `
      ${legend}
      <div class="stt-view">
        ${lines
          .map((line, index) => {
            const originLine = getComparableOriginLine(originLines, line, index);
            const highlightedText = hasOrigin && originLine
              ? renderTokenDiffText(line.text, originLine.text)
              : escapeHtml(line.text);

            if (line.type === "speaker") {
              return `
                <div class="stt-line ${line.speakerClass}">
                  <span class="stt-speaker">${escapeHtml(line.speaker)}</span>
                  <p class="stt-utterance">${highlightedText}</p>
                </div>
              `;
            }

            return `
              <div class="stt-line plain">
                <p class="stt-utterance">${highlightedText}</p>
              </div>
            `;
          })
          .join("")}
      </div>
    `;
  }

  function getComparableOriginLine(originLines, currentLine, index) {
    const originLine = originLines[index];
    if (!originLine || originLine.type !== currentLine.type) {
      return null;
    }

    if (currentLine.type === "speaker" && originLine.speaker !== currentLine.speaker) {
      return null;
    }

    return originLine;
  }

  function renderTokenDiffText(currentText, originText) {
    const currentTokens = tokenizeDiffText(currentText);
    const originCounts = countOriginTokens(originText);

    return currentTokens
      .map((token) => {
        if (token.isWhitespace) {
          return escapeHtml(token.text);
        }

        const normalized = normalizeDiffToken(token.text);
        const remaining = originCounts.get(normalized) || 0;
        if (remaining > 0) {
          originCounts.set(normalized, remaining - 1);
          return escapeHtml(token.text);
        }

        return `<span class="stt-token added">${escapeHtml(token.text)}</span>`;
      })
      .join("");
  }

  function tokenizeDiffText(value) {
    return String(value || "")
      .split(/(\s+)/)
      .filter(Boolean)
      .map((token) => ({
        text: token,
        isWhitespace: /^\s+$/.test(token),
      }));
  }

  function countOriginTokens(value) {
    const counts = new Map();
    tokenizeDiffText(value).forEach((token) => {
      if (token.isWhitespace) {
        return;
      }

      const normalized = normalizeDiffToken(token.text);
      counts.set(normalized, (counts.get(normalized) || 0) + 1);
    });
    return counts;
  }

  function normalizeDiffToken(value) {
    return String(value || "").trim().toLowerCase();
  }

  function formatSttLines(value) {
    const normalized = String(value || "")
      .replace(/\r\n/g, "\n")
      .replace(/\r/g, "\n")
      .replace(new RegExp(`\\s*(${speakerAgent}|${speakerCustomer})\\s*:\\s*`, "g"), "\n$1: ")
      .trim();

    if (!normalized) {
      return [];
    }

    return normalized
      .split(/\n+/)
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => {
        const match = line.match(new RegExp(`^(${speakerAgent}|${speakerCustomer}):\\s*(.*)$`));
        if (!match) {
          return { type: "plain", text: line };
        }

        return {
          type: "speaker",
          speaker: match[1],
          speakerClass: match[1] === speakerAgent ? "agent" : "customer",
          text: match[2] || "-",
        };
      });
  }

  function parseStructuredValue(rawValue) {
    if (!rawValue || rawValue === "-") {
      return null;
    }

    const trimmed = rawValue.trim();
    if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) {
      return null;
    }

    try {
      return JSON.parse(trimmed);
    } catch (error) {
      return null;
    }
  }

  function renderStructuredValue(value, fieldName) {
    const kind = Array.isArray(value) ? "array" : "object";
    const meta = kind === "array" ? `${value.length} items` : `${Object.keys(value).length} fields`;

    return `
      <div class="json-view">
        <div class="json-toolbar">
          <span class="json-badge">${kind}</span>
          <span class="json-meta">${meta}</span>
        </div>
        ${renderJsonNode(value, `${fieldName}`)}
        <details class="json-raw">
          <summary>raw JSON</summary>
          <pre class="field-value">${escapeHtml(JSON.stringify(value, null, 2))}</pre>
        </details>
      </div>
    `;
  }

  function renderJsonNode(value, path) {
    if (value == null) {
      return '<span class="json-scalar null">null</span>';
    }

    if (Array.isArray(value)) {
      if (!value.length) {
        return '<div class="json-empty">[]</div>';
      }

      return `
        <div class="json-array">
          ${value
            .map((item, index) => {
              const label = describeJsonItem(item, `${path}[${index}]`);
              const node = isPlainObject(item) || Array.isArray(item)
                ? renderJsonNode(item, `${path}[${index}]`)
                : renderJsonScalar(item);
              return `
                <div class="json-array-item">
                  <div class="json-array-index">${escapeHtml(label)}</div>
                  <div class="json-array-content">${node}</div>
                </div>
              `;
            })
            .join("")}
        </div>
      `;
    }

    if (isPlainObject(value)) {
      const entries = Object.entries(value);
      if (!entries.length) {
        return '<div class="json-empty">{}</div>';
      }

      return `
        <div class="json-object">
          ${entries
            .map(([key, item]) => {
              const node = isPlainObject(item) || Array.isArray(item)
                ? renderJsonNode(item, `${path}.${key}`)
                : renderJsonScalar(item);
              return `
                <div class="json-row">
                  <div class="json-key">${escapeHtml(key)}</div>
                  <div class="json-node">${node}</div>
                </div>
              `;
            })
            .join("")}
        </div>
      `;
    }

    return renderJsonScalar(value);
  }

  function renderJsonScalar(value) {
    if (typeof value === "boolean") {
      return `<span class="json-scalar boolean">${value}</span>`;
    }

    if (typeof value === "number") {
      return `<span class="json-scalar number">${value}</span>`;
    }

    if (value == null) {
      return '<span class="json-scalar null">null</span>';
    }

    const text = String(value);
    const scalarClass = text.length > 80 ? "json-scalar string block" : "json-scalar string";
    return `<span class="${scalarClass}">${escapeHtml(text)}</span>`;
  }

  function describeJsonItem(value, fallback) {
    if (isPlainObject(value)) {
      if (value.keyword) return value.keyword;
      if (value.label) return value.label;
      if (value.canonical) return value.canonical;
      if (value.speaker) return value.speaker;
      if (value.utterance_id != null) return `utterance ${value.utterance_id}`;
    }

    return fallback;
  }

  function isPlainObject(value) {
    return Object.prototype.toString.call(value) === "[object Object]";
  }

  function moveSelection(step) {
    if (!state.filteredRows.length) {
      return;
    }

    state.selectedRowIndex = Math.max(0, Math.min(state.filteredRows.length - 1, state.selectedRowIndex + step));
    renderRowList();
    renderRecord();
  }

  function markDecision(result) {
    const dataset = state.loadedDatasets.get(state.selectedDatasetKey);
    const row = state.filteredRows[state.selectedRowIndex];
    if (!dataset || !row) {
      return;
    }

    const rowKey = getRowKey(dataset, row);
    state.results[dataset.key] = state.results[dataset.key] || {};
    state.results[dataset.key][rowKey] = {
      result,
      note: getNote(dataset.key, rowKey),
      updatedAt: new Date().toISOString(),
    };
    saveResults();
    renderRowList();
    renderSummary();
    renderRecord();
  }

  function onNoteChange() {
    const dataset = state.loadedDatasets.get(state.selectedDatasetKey);
    const row = state.filteredRows[state.selectedRowIndex];
    if (!dataset || !row) {
      return;
    }

    const rowKey = getRowKey(dataset, row);
    state.results[dataset.key] = state.results[dataset.key] || {};
    state.results[dataset.key][rowKey] = {
      result: getDecision(dataset.key, rowKey),
      note: dom.noteInput.value,
      updatedAt: new Date().toISOString(),
    };
    saveResults();
  }

  function exportCurrentDataset() {
    const dataset = state.loadedDatasets.get(state.selectedDatasetKey);
    if (!dataset) {
      return;
    }
    downloadCsv(`${dataset.version}-${dataset.fileBaseName}-review-results.csv`, collectExportRows([dataset]));
  }

  function exportAllDatasets() {
    Promise.all(state.index.datasets.map((entry) => loadDatasetScript(entry)))
      .then((datasets) => {
        downloadCsv("quality-review-results-all.csv", collectExportRows(datasets));
      })
      .catch((error) => {
        window.alert(`Failed to load all datasets: ${error.message}`);
      });
  }

  function collectExportRows(datasets) {
    const rows = [];
    datasets.forEach((dataset) => {
      dataset.rows.forEach((row) => {
        const rowKey = getRowKey(dataset, row);
        const review = (state.results[dataset.key] || {})[rowKey] || {};
        rows.push({
          dataset_key: dataset.key,
          version: dataset.version,
          file_name: dataset.fileName,
          row_index: row.rowIndex,
          row_key: rowKey,
          review_result: review.result || "",
          review_note: review.note || "",
          updated_at: review.updatedAt || "",
          sample_id: row.values.sample_id || "",
          source_case_id: row.values.source_case_id || "",
          split: row.values.split || "",
          intent_type: row.values.intent_type || "",
          answer_style: row.values.answer_style || "",
        });
      });
    });
    return rows;
  }

  function downloadCsv(fileName, rows) {
    const headers = [
      "dataset_key",
      "version",
      "file_name",
      "row_index",
      "row_key",
      "review_result",
      "review_note",
      "updated_at",
      "sample_id",
      "source_case_id",
      "split",
      "intent_type",
      "answer_style",
    ];

    const csv = [headers.join(",")]
      .concat(rows.map((row) => headers.map((header) => toCsvCell(row[header])).join(",")))
      .join("\r\n");

    const blob = new Blob(["\ufeff" + csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = fileName;
    link.click();
    URL.revokeObjectURL(url);
  }

  function renderEmpty(message) {
    dom.datasetTitle.textContent = message;
    dom.datasetMeta.textContent = "";
    dom.rowList.innerHTML = `<div class="empty-state">${escapeHtml(message)}</div>`;
    dom.fieldGrid.innerHTML = `<div class="empty-state">${escapeHtml(message)}</div>`;
  }

  function matchesQuery(row, query) {
    if (!query) {
      return true;
    }

    return Object.values(row.values).some((value) => String(value || "").toLowerCase().includes(query));
  }

  function getRowKey(dataset, row) {
    return row.values.sample_id || row.values.source_case_id || `${dataset.key}#${row.rowIndex}`;
  }

  function getDecision(datasetKey, rowKey) {
    return state.results[datasetKey] && state.results[datasetKey][rowKey]
      ? state.results[datasetKey][rowKey].result || ""
      : "";
  }

  function getNote(datasetKey, rowKey) {
    return state.results[datasetKey] && state.results[datasetKey][rowKey]
      ? state.results[datasetKey][rowKey].note || ""
      : "";
  }

  function loadResults() {
    try {
      return JSON.parse(localStorage.getItem(storageKey) || "{}");
    } catch (error) {
      return {};
    }
  }

  function saveResults() {
    localStorage.setItem(storageKey, JSON.stringify(state.results));
  }

  function shorten(text, limit) {
    return text.length > limit ? `${text.slice(0, limit - 1)}...` : text;
  }

  function toCsvCell(value) {
    const text = String(value == null ? "" : value);
    return `"${text.replace(/"/g, '""')}"`;
  }

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }
})();