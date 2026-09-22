import {
  mbmot_close,
  mbmot_convert_yolo_frame,
  mbmot_create,
  mbmot_reset,
  mbmot_update,
} from "./mbmot.js";
import { addRule, buildRunReport, cloneRules, defaultRules, movePoint, removeRule, setupJson, summaryCounts } from "./workbench.mjs";

const FPS = 10;
const DEFAULT_FRAME_COUNT = 90;
const video = document.querySelector("#video");
const canvas = document.querySelector("#overlay");
const context = canvas.getContext("2d");
const message = document.querySelector("#stage-message");
const timeline = document.querySelector("#timeline");
const frameLabel = document.querySelector("#frame-label");
const playButton = document.querySelector("#play");
const stepButton = document.querySelector("#step");
const restartButton = document.querySelector("#restart");
const downloadButton = document.querySelector("#download");
const eventList = document.querySelector("#event-list");
const classCounts = document.querySelector("#class-counts");
const statusDot = document.querySelector("#status-dot");
const statusText = document.querySelector("#engine-status");
const videoFile = document.querySelector("#video-file");
const detectionFile = document.querySelector("#detection-file");
const ruleSelect = document.querySelector("#rule-select");
const pointEditor = document.querySelector("#point-editor");
const addRuleButton = document.querySelector("#add-rule");
const removeRuleButton = document.querySelector("#remove-rule");
const codeTabs = Array.from(document.querySelectorAll("[data-code-tab]"));

const metrics = {
  tracks: document.querySelector("#metric-tracks"),
  occupancy: document.querySelector("#metric-occupancy"),
  ltr: document.querySelector("#metric-ltr"),
  rtl: document.querySelector("#metric-rtl"),
  entries: document.querySelector("#metric-entries"),
  unique: document.querySelector("#metric-unique"),
};

let detections = [];
let results = [];
let sessionId = null;
let processedFrame = 0;
let animationId = null;
let dragHandle = null;
let activeMode = "line";
let uploadedVideoUrl = null;
let playbackFps = FPS;
let rules = defaultRules(768, 576);
let selectedRuleId = 1;
let dragOrigin = null;
let dataSource = { name: "默认样例", format: "xyxy", width: 768, height: 576 };

function updatePlaybackFps() {
  if (Number.isFinite(video.duration) && video.duration > 0 && detections.length > 0) {
    playbackFps = detections.length / video.duration;
  }
}

function parseBridge(text) {
  const response = JSON.parse(text);
  if (!response.ok) {
    throw new Error(response.message || response.code || "MoonBit 引擎返回错误");
  }
  return response.result;
}

function createSession() {
  const created = parseBridge(mbmot_create(setupJson(rules)));
  if (sessionId !== null) mbmot_close(sessionId);
  sessionId = created.session_id;
  processedFrame = 0;
  results = [];
}

function currentCollection() {
  return activeMode === "line" ? rules.lines : rules.regions;
}

function currentRule() {
  return currentCollection().find((rule) => rule.id === selectedRuleId) || null;
}

function currentPoints() {
  const rule = currentRule();
  if (!rule) return [];
  return activeMode === "line" ? [rule.start, rule.end] : rule.vertices;
}

function syncRuleEditor() {
  const collection = currentCollection();
  if (!collection.some((rule) => rule.id === selectedRuleId)) selectedRuleId = collection[0]?.id ?? null;
  ruleSelect.replaceChildren(...collection.map((rule) => {
    const option = document.createElement("option");
    option.value = String(rule.id);
    option.textContent = `${activeMode === "line" ? "线" : "区域"} ${rule.id}`;
    return option;
  }));
  ruleSelect.disabled = collection.length === 0;
  removeRuleButton.disabled = collection.length === 0;
  if (selectedRuleId !== null) ruleSelect.value = String(selectedRuleId);
  pointEditor.replaceChildren(...currentPoints().map(([x, y], index) => {
    const group = document.createElement("div");
    group.className = "point-pair";
    const title = document.createElement("span");
    title.textContent = activeMode === "line" ? (index === 0 ? "起点" : "终点") : `顶点 ${index + 1}`;
    group.append(title);
    for (const [axis, value, max] of [["X", x, canvas.width], ["Y", y, canvas.height]]) {
      const label = document.createElement("label");
      label.textContent = axis;
      const input = document.createElement("input");
      input.type = "number";
      input.min = "0";
      input.max = String(max);
      input.step = "any";
      input.value = String(Math.round(value * 100) / 100);
      input.setAttribute("aria-label", `${title.textContent} ${axis}`);
      input.addEventListener("change", () => {
        try {
          const coordinate = Number(input.value);
          const updated = [x, y];
          updated[axis === "X" ? 0 : 1] = coordinate;
          applyRules(movePoint(rules, activeMode, selectedRuleId, index, updated, canvas.width, canvas.height));
        } catch (error) {
          setStatus(error.message, "error");
          syncRuleEditor();
        }
      });
      label.append(input);
      group.append(label);
    }
    return group;
  }));
  if (collection.length === 0) pointEditor.textContent = "当前没有规则。可点击“添加”。";
}

function applyRules(next) {
  const previous = rules;
  const target = processedFrame;
  rules = next;
  try {
    createSession();
    processUntil(target);
    syncRuleEditor();
    setStatus("规则已更新，结果已从第一帧重算");
  } catch (error) {
    rules = previous;
    createSession();
    processUntil(target);
    syncRuleEditor();
    throw error;
  }
}

function setStatus(text, kind = "ready") {
  statusText.textContent = text;
  statusDot.className = `status-dot ${kind}`;
}

function showMessage(text) {
  message.textContent = text;
  message.hidden = false;
}

function hideMessage() {
  message.hidden = true;
}

function parseNdjson(text) {
  const rows = [];
  let format = null;
  for (const [index, raw] of text.split(/\r?\n/).entries()) {
    const line = raw.trim();
    if (!line) continue;
    let input;
    try {
      input = JSON.parse(line);
    } catch (error) {
      throw new Error(`检测文件第 ${index + 1} 行不是有效 JSON：${error.message}`);
    }
    if (input === null || typeof input !== "object" || Array.isArray(input)) {
      throw new Error(`检测文件第 ${index + 1} 行必须是帧对象`);
    }
    const lineFormat = Object.hasOwn(input, "coordinates") ? "yolo_cxcywh" : "xyxy";
    if (format !== null && lineFormat !== format) throw new Error(`检测文件第 ${index + 1} 行与前面使用了不同格式`);
    format = lineFormat;
    let row = input;
    if (format === "yolo_cxcywh") {
      try {
        row = parseBridge(mbmot_convert_yolo_frame(line));
      } catch (error) {
        throw new Error(`检测文件第 ${index + 1} 行：${error.message}`);
      }
      if (input.width !== canvas.width || input.height !== canvas.height) {
        throw new Error(`检测文件第 ${index + 1} 行的宽高与录像画面不一致`);
      }
    }
    if (row.frame !== rows.length + 1 || !Array.isArray(row.detections)) {
      throw new Error(`检测文件第 ${index + 1} 行必须对应帧 ${rows.length + 1}`);
    }
    rows.push(row);
  }
  return { rows, format: format || "xyxy" };
}

async function loadDefaultData() {
  const response = await fetch("./assets/detections.ndjson");
  if (!response.ok) {
    throw new Error(`无法读取默认检测流（HTTP ${response.status}）`);
  }
  detections = parseNdjson(await response.text()).rows;
  timeline.max = String(detections.length || DEFAULT_FRAME_COUNT);
}

function eventText(event, frame) {
  if (event.type === "line_crossed") {
    const direction = event.direction === "left_to_right" ? "从左到右" : "从右到左";
    return `帧 ${frame} · 轨迹 ${event.track_id} ${direction}越过线 ${event.line_id}`;
  }
  if (event.type === "region_entered") {
    return `帧 ${frame} · 轨迹 ${event.track_id} 进入区域 ${event.region_id}${event.initial ? "（初始已在区域内）" : ""}`;
  }
  return `帧 ${frame} · 轨迹 ${event.track_id} 离开区域 ${event.region_id}，停留 ${event.dwell_frames} 帧`;
}

function renderClassCounts(analytics) {
  const rows = [];
  for (const count of analytics.line_class_counts || []) {
    rows.push({
      label: `线 ${count.line_id} · 类别 ${count.class_id}`,
      value: `左 ${count.left_to_right} · 右 ${count.right_to_left}`,
    });
  }
  for (const count of analytics.region_class_counts || []) {
    rows.push({
      label: `区域 ${count.region_id} · 类别 ${count.class_id}`,
      value: `占用 ${count.current_occupancy} · 进入 ${count.entries}`,
    });
  }
  if (rows.length === 0) {
    classCounts.innerHTML = '<p class="empty-class-count">当前还没有分类统计。</p>';
    return;
  }
  classCounts.replaceChildren(
    ...rows.map(({ label, value }) => {
      const row = document.createElement("div");
      row.className = "class-count-row";
      const name = document.createElement("span");
      name.textContent = label;
      const result = document.createElement("strong");
      result.textContent = value;
      row.append(name, result);
      return row;
    }),
  );
}

function updatePanel(result) {
  if (!result) {
    Object.values(metrics).forEach((element) => {
      element.textContent = "0";
    });
    classCounts.innerHTML = '<p class="empty-class-count">播放录像后按类别显示规则统计。</p>';
    eventList.innerHTML = '<li class="empty-event">播放录像后显示越线和区域事件。</li>';
    downloadButton.disabled = true;
    return;
  }
  const tracking = result.tracking;
  const analytics = result.analytics;
  const totals = summaryCounts(analytics);
  metrics.tracks.textContent = String(tracking.tracks.length);
  metrics.occupancy.textContent = String(totals.occupancy);
  metrics.ltr.textContent = String(totals.left_to_right);
  metrics.rtl.textContent = String(totals.right_to_left);
  metrics.entries.textContent = String(totals.entries);
  metrics.unique.textContent = String(totals.unique_region_tracks);
  renderClassCounts(analytics);
  const events = results
    .flatMap((entry) => entry.analytics.events.map((event) => ({ frame: entry.tracking.frame, event })))
    .slice(-8)
    .reverse();
  if (events.length === 0) {
    eventList.innerHTML = '<li class="empty-event">当前进度尚未确认空间事件。</li>';
  } else {
    eventList.replaceChildren(
      ...events.map(({ frame, event }) => {
        const item = document.createElement("li");
        item.textContent = eventText(event, frame);
        return item;
      }),
    );
  }
  downloadButton.disabled = results.length === 0;
}

function processUntil(targetFrame) {
  const safeTarget = Math.max(0, Math.min(targetFrame, detections.length));
  if (safeTarget < processedFrame) {
    createSession();
  }
  for (let frame = processedFrame + 1; frame <= safeTarget; frame += 1) {
    const output = parseBridge(mbmot_update(sessionId, JSON.stringify(detections[frame - 1])));
    results.push(output);
    processedFrame = frame;
  }
  const current = results[safeTarget - 1] || null;
  updatePanel(current);
  timeline.value = String(safeTarget);
  frameLabel.textContent = `${safeTarget} / ${detections.length}`;
  draw(current);
}

function drawRules() {
  context.save();
  context.lineJoin = "round";
  context.lineCap = "round";
  for (const region of rules.regions) {
    context.beginPath();
    context.moveTo(...region.vertices[0]);
    region.vertices.slice(1).forEach((point) => context.lineTo(...point));
    context.closePath();
    context.fillStyle = "rgba(109, 229, 223, 0.08)";
    context.fill();
    context.strokeStyle = "#6de5df";
    context.lineWidth = activeMode === "region" && selectedRuleId === region.id ? 4 : 2;
    context.stroke();
    context.fillStyle = "#6de5df";
    context.font = "14px system-ui";
    context.fillText(`区域 ${region.id}`, region.vertices[0][0] + 5, region.vertices[0][1] - 7);
  }
  for (const line of rules.lines) {
    context.beginPath();
    context.moveTo(...line.start);
    context.lineTo(...line.end);
    context.strokeStyle = "#f4c54f";
    context.lineWidth = activeMode === "line" && selectedRuleId === line.id ? 5 : 3;
    context.stroke();
    context.fillStyle = "#f4c54f";
    context.font = "14px system-ui";
    context.fillText(`线 ${line.id}`, line.start[0] + 5, line.start[1] - 7);
  }
  context.fillStyle = activeMode === "line" ? "#f4c54f" : "#6de5df";
  currentPoints().forEach(([x, y]) => {
    context.beginPath();
    context.arc(x, y, 8, 0, Math.PI * 2);
    context.fill();
    context.strokeStyle = "#071014";
    context.lineWidth = 2;
    context.stroke();
  });
  context.restore();
}

function drawTracks(result) {
  if (!result) return;
  context.save();
  context.font = "700 16px system-ui";
  result.tracking.tracks.forEach((track) => {
    const [x1, y1, x2, y2] = track.xyxy;
    context.strokeStyle = "#70f0a8";
    context.lineWidth = 3;
    context.strokeRect(x1, y1, x2 - x1, y2 - y1);
    const label = `ID ${track.track_id} · ${track.score.toFixed(2)}`;
    const width = context.measureText(label).width + 12;
    context.fillStyle = "rgba(5, 9, 12, 0.86)";
    context.fillRect(x1, Math.max(0, y1 - 25), width, 24);
    context.fillStyle = "#eef7f8";
    context.fillText(label, x1 + 6, Math.max(17, y1 - 7));
  });
  context.restore();
}

function draw(result = results[processedFrame - 1] || null) {
  context.clearRect(0, 0, canvas.width, canvas.height);
  drawRules();
  drawTracks(result);
}

function pointerPosition(event) {
  const rect = canvas.getBoundingClientRect();
  return [
    ((event.clientX - rect.left) / rect.width) * canvas.width,
    ((event.clientY - rect.top) / rect.height) * canvas.height,
  ];
}

canvas.addEventListener("pointerdown", (event) => {
  const point = pointerPosition(event);
  let nearest = null;
  let distance = Number.POSITIVE_INFINITY;
  for (const rule of currentCollection()) {
    const points = activeMode === "line" ? [rule.start, rule.end] : rule.vertices;
    points.forEach(([x, y], index) => {
      const candidate = Math.hypot(point[0] - x, point[1] - y);
      if (candidate < distance) {
        distance = candidate;
        nearest = { id: rule.id, index };
      }
    });
  }
  if (distance <= 28 && nearest) {
    selectedRuleId = nearest.id;
    syncRuleEditor();
    dragOrigin = cloneRules(rules);
    dragHandle = nearest;
    canvas.setPointerCapture(event.pointerId);
  }
});

canvas.addEventListener("pointermove", (event) => {
  if (dragHandle === null) return;
  const point = pointerPosition(event);
  rules = movePoint(rules, activeMode, dragHandle.id, dragHandle.index, [
    Math.max(0, Math.min(canvas.width, point[0])),
    Math.max(0, Math.min(canvas.height, point[1])),
  ], canvas.width, canvas.height);
  draw();
});

canvas.addEventListener("pointerup", async (event) => {
  if (dragHandle === null) return;
  dragHandle = null;
  canvas.releasePointerCapture(event.pointerId);
  const candidate = rules;
  rules = dragOrigin;
  dragOrigin = null;
  try {
    applyRules(candidate);
  } catch (error) {
    setStatus(error.message, "error");
  }
});

canvas.addEventListener("pointercancel", () => {
  if (dragOrigin === null) return;
  rules = dragOrigin;
  dragOrigin = null;
  dragHandle = null;
  syncRuleEditor();
  draw();
});

ruleSelect.addEventListener("change", () => {
  selectedRuleId = Number(ruleSelect.value);
  syncRuleEditor();
  draw();
});

addRuleButton.addEventListener("click", () => {
  try {
    const added = addRule(rules, activeMode, canvas.width, canvas.height);
    applyRules(added.rules);
    selectedRuleId = added.id;
    syncRuleEditor();
    draw();
  } catch (error) {
    setStatus(error.message, "error");
  }
});

removeRuleButton.addEventListener("click", () => {
  try {
    applyRules(removeRule(rules, activeMode, selectedRuleId));
    draw();
  } catch (error) {
    setStatus(error.message, "error");
  }
});

document.querySelectorAll(".mode").forEach((button) => {
  button.addEventListener("click", () => {
    activeMode = button.dataset.mode;
    selectedRuleId = currentCollection()[0]?.id ?? null;
    document.querySelectorAll(".mode").forEach((item) => {
      const active = item === button;
      item.classList.toggle("active", active);
      item.setAttribute("aria-pressed", String(active));
    });
    syncRuleEditor();
    draw();
  });
});

function activateCodeTab(selected, focus = false) {
  codeTabs.forEach((tab) => {
    const active = tab === selected;
    tab.classList.toggle("active", active);
    tab.setAttribute("aria-selected", String(active));
    tab.tabIndex = active ? 0 : -1;
    document.querySelector(`#panel-${tab.dataset.codeTab}`).hidden = !active;
  });
  if (focus) selected.focus();
}

codeTabs.forEach((tab, index) => {
  tab.addEventListener("click", () => activateCodeTab(tab));
  tab.addEventListener("keydown", (event) => {
    let target = null;
    if (event.key === "ArrowRight") target = codeTabs[(index + 1) % codeTabs.length];
    if (event.key === "ArrowLeft") target = codeTabs[(index - 1 + codeTabs.length) % codeTabs.length];
    if (event.key === "Home") target = codeTabs[0];
    if (event.key === "End") target = codeTabs[codeTabs.length - 1];
    if (target) {
      event.preventDefault();
      activateCodeTab(target, true);
    }
  });
});

function tick() {
  if (!video.paused && !video.ended) {
    const target = Math.min(detections.length, Math.floor(video.currentTime * playbackFps) + 1);
    try {
      processUntil(target);
    } catch (error) {
      video.pause();
      setStatus(error.message, "error");
      showMessage(error.message);
    }
    animationId = requestAnimationFrame(tick);
  }
}

playButton.addEventListener("click", async () => {
  if (video.paused) {
    if (video.ended || processedFrame >= detections.length) {
      video.currentTime = 0;
      createSession();
      processUntil(0);
    }
    await video.play();
  } else {
    video.pause();
  }
});

video.addEventListener("play", () => {
  playButton.textContent = "暂停";
  hideMessage();
  cancelAnimationFrame(animationId);
  tick();
});

video.addEventListener("pause", () => {
  playButton.textContent = "播放";
  cancelAnimationFrame(animationId);
});

video.addEventListener("ended", () => {
  playButton.textContent = "重播";
});

stepButton.addEventListener("click", () => {
  video.pause();
  const target = Math.min(detections.length, processedFrame + 1);
  video.currentTime = Math.max(0, (target - 1) / playbackFps);
  try {
    processUntil(target);
  } catch (error) {
    setStatus(error.message, "error");
    showMessage(error.message);
  }
});

restartButton.addEventListener("click", () => {
  video.pause();
  video.currentTime = 0;
  createSession();
  processUntil(0);
  setStatus("MoonBit 引擎已重置");
});

timeline.addEventListener("input", () => {
  video.pause();
  const target = Number(timeline.value);
  video.currentTime = target === 0 ? 0 : (target - 1) / playbackFps;
  try {
    processUntil(target);
  } catch (error) {
    setStatus(error.message, "error");
  }
});

downloadButton.addEventListener("click", async () => {
  try {
    const encoded = new TextEncoder().encode(`${detections.map((frame) => JSON.stringify(frame)).join("\n")}\n`);
    const digest = await crypto.subtle.digest("SHA-256", encoded);
    const replay_sha256 = [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, "0")).join("");
    const report = buildRunReport(detections, results, rules, { ...dataSource, replay_sha256 });
    const url = URL.createObjectURL(new Blob([`${JSON.stringify(report, null, 2)}\n`], { type: "application/json" }));
    const link = document.createElement("a");
    link.href = url;
    link.download = "mbmot-run-report.json";
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  } catch (error) {
    setStatus(`报告生成失败：${error.message}`, "error");
  }
});

videoFile.addEventListener("change", async () => {
  const [file] = videoFile.files;
  if (!file) return;
  if (uploadedVideoUrl) URL.revokeObjectURL(uploadedVideoUrl);
  uploadedVideoUrl = URL.createObjectURL(file);
  video.src = uploadedVideoUrl;
  await new Promise((resolve) => video.addEventListener("loadedmetadata", resolve, { once: true }));
  canvas.width = video.videoWidth;
  canvas.height = video.videoHeight;
  rules = defaultRules(canvas.width, canvas.height);
  selectedRuleId = 1;
  detections = [];
  timeline.max = "0";
  dataSource = { name: "尚未选择检测流", format: "xyxy", width: canvas.width, height: canvas.height };
  createSession();
  processUntil(0);
  syncRuleEditor();
  setStatus("已载入本地录像，请继续选择匹配的检测流");
});

detectionFile.addEventListener("change", async () => {
  const [file] = detectionFile.files;
  if (!file) return;
  try {
    const parsed = parseNdjson(await file.text());
    detections = parsed.rows;
    dataSource = { name: file.name, format: parsed.format, width: canvas.width, height: canvas.height };
    updatePlaybackFps();
    timeline.max = String(detections.length);
    createSession();
    processUntil(0);
    setStatus(`已载入 ${detections.length} 帧检测结果`);
  } catch (error) {
    setStatus(error.message, "error");
  }
});

async function loadBenchmark() {
  try {
    const response = await fetch("./assets/benchmark-report.json");
    if (!response.ok) return;
    const report = await response.json();
    const container = document.querySelector("#benchmark-result");
    container.innerHTML = `
      <strong>${report.dataset} · ${report.sequence}</strong>
      <table class="benchmark-table">
        <thead><tr><th>帧数</th><th>MOTA</th><th>IDF1</th><th>IDSW</th><th>跟踪耗时</th></tr></thead>
        <tbody><tr><td>${report.frames}</td><td>${report.mota}</td><td>${report.idf1}</td><td>${report.identity_switches}</td><td>${report.tracking_time_ms} ms</td></tr></tbody>
      </table>`;
    container.hidden = false;
    document.querySelector("#benchmark-empty").hidden = true;
  } catch {
    // No benchmark card is preferable to displaying a result that was not loaded.
  }
}

async function start() {
  try {
    await Promise.all([
      loadDefaultData(),
      new Promise((resolve, reject) => {
        if (video.readyState >= 1) resolve();
        else {
          video.addEventListener("loadedmetadata", resolve, { once: true });
          video.addEventListener("error", () => reject(new Error("默认录像无法加载")), { once: true });
        }
      }),
    ]);
    canvas.width = video.videoWidth || 768;
    canvas.height = video.videoHeight || 576;
    updatePlaybackFps();
    rules = defaultRules(canvas.width, canvas.height);
    selectedRuleId = 1;
    dataSource = { name: "默认样例", format: "xyxy", width: canvas.width, height: canvas.height };
    createSession();
    processUntil(0);
    syncRuleEditor();
    hideMessage();
    setStatus("MoonBit 引擎已就绪");
    await loadBenchmark();
  } catch (error) {
    setStatus(error.message, "error");
    showMessage(error.message);
  }
}

window.addEventListener("beforeunload", () => {
  if (sessionId !== null) mbmot_close(sessionId);
  if (uploadedVideoUrl) URL.revokeObjectURL(uploadedVideoUrl);
});

start();
