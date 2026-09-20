import {
  mbmot_close,
  mbmot_create,
  mbmot_reset,
  mbmot_update,
} from "./mbmot.js";

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
const statusDot = document.querySelector("#status-dot");
const statusText = document.querySelector("#engine-status");
const videoFile = document.querySelector("#video-file");
const detectionFile = document.querySelector("#detection-file");

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
let rules = defaultRules(768, 576);

function defaultRules(width, height) {
  return {
    line: [
      [width * 0.5, height * 0.05],
      [width * 0.5, height * 0.95],
    ],
    region: [
      [width * 0.1, height * 0.25],
      [width * 0.9, height * 0.25],
      [width * 0.9, height * 0.95],
      [width * 0.1, height * 0.95],
    ],
  };
}

function setupJson() {
  return JSON.stringify({
    config: { anchor: "bottom_center", stable_frames: 2 },
    lines: [{ id: 1, start: rules.line[0], end: rules.line[1] }],
    regions: [{ id: 1, vertices: rules.region }],
  });
}

function parseBridge(text) {
  const response = JSON.parse(text);
  if (!response.ok) {
    throw new Error(response.message || response.code || "MoonBit 引擎返回错误");
  }
  return response.result;
}

function createSession() {
  if (sessionId !== null) {
    mbmot_close(sessionId);
  }
  const created = parseBridge(mbmot_create(setupJson()));
  sessionId = created.session_id;
  processedFrame = 0;
  results = [];
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
  const rows = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line, index) => {
      try {
        return JSON.parse(line);
      } catch (error) {
        throw new Error(`检测文件第 ${index + 1} 行不是有效 JSON：${error.message}`);
      }
    });
  rows.forEach((row, index) => {
    if (row.frame !== index + 1 || !Array.isArray(row.detections)) {
      throw new Error(`检测文件第 ${index + 1} 行必须对应帧 ${index + 1}`);
    }
  });
  return rows;
}

async function loadDefaultData() {
  const response = await fetch("./assets/detections.ndjson");
  if (!response.ok) {
    throw new Error(`无法读取默认检测流（HTTP ${response.status}）`);
  }
  detections = parseNdjson(await response.text());
  timeline.max = String(detections.length || DEFAULT_FRAME_COUNT);
}

function eventText(event, frame) {
  if (event.type === "line_crossed") {
    const direction = event.direction === "left_to_right" ? "从左到右" : "从右到左";
    return `帧 ${frame} · 轨迹 ${event.track_id} ${direction}越过计数线`;
  }
  if (event.type === "region_entered") {
    return `帧 ${frame} · 轨迹 ${event.track_id} 进入区域${event.initial ? "（初始已在区域内）" : ""}`;
  }
  return `帧 ${frame} · 轨迹 ${event.track_id} 离开区域，停留 ${event.dwell_frames} 帧`;
}

function updatePanel(result) {
  if (!result) {
    Object.values(metrics).forEach((element) => {
      element.textContent = "0";
    });
    eventList.innerHTML = '<li class="empty-event">播放录像后，这里会出现进入、退出和越线事件。</li>';
    downloadButton.disabled = true;
    return;
  }
  const tracking = result.tracking;
  const analytics = result.analytics;
  const line = analytics.line_counts[0] || {};
  const region = analytics.region_counts[0] || {};
  metrics.tracks.textContent = String(tracking.tracks.length);
  metrics.occupancy.textContent = String(region.current_occupancy || 0);
  metrics.ltr.textContent = String(line.left_to_right || 0);
  metrics.rtl.textContent = String(line.right_to_left || 0);
  metrics.entries.textContent = String(region.entries || 0);
  metrics.unique.textContent = String(region.unique_tracks || 0);
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

  context.beginPath();
  context.moveTo(...rules.region[0]);
  rules.region.slice(1).forEach((point) => context.lineTo(...point));
  context.closePath();
  context.fillStyle = "rgba(109, 229, 223, 0.12)";
  context.fill();
  context.strokeStyle = "#6de5df";
  context.lineWidth = activeMode === "region" ? 4 : 2;
  context.stroke();

  context.beginPath();
  context.moveTo(...rules.line[0]);
  context.lineTo(...rules.line[1]);
  context.strokeStyle = "#f4c54f";
  context.lineWidth = activeMode === "line" ? 5 : 3;
  context.stroke();

  const handles = activeMode === "line" ? rules.line : rules.region;
  context.fillStyle = activeMode === "line" ? "#f4c54f" : "#6de5df";
  handles.forEach(([x, y]) => {
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
  const handles = activeMode === "line" ? rules.line : rules.region;
  let nearest = -1;
  let distance = Number.POSITIVE_INFINITY;
  handles.forEach(([x, y], index) => {
    const candidate = Math.hypot(point[0] - x, point[1] - y);
    if (candidate < distance) {
      distance = candidate;
      nearest = index;
    }
  });
  if (distance <= 28) {
    dragHandle = nearest;
    canvas.setPointerCapture(event.pointerId);
  }
});

canvas.addEventListener("pointermove", (event) => {
  if (dragHandle === null) return;
  const point = pointerPosition(event);
  const handles = activeMode === "line" ? rules.line : rules.region;
  handles[dragHandle] = [
    Math.max(0, Math.min(canvas.width, point[0])),
    Math.max(0, Math.min(canvas.height, point[1])),
  ];
  draw();
});

canvas.addEventListener("pointerup", async (event) => {
  if (dragHandle === null) return;
  dragHandle = null;
  canvas.releasePointerCapture(event.pointerId);
  const target = processedFrame;
  try {
    createSession();
    processUntil(target);
    setStatus("规则已更新，结果已从第一帧重算");
  } catch (error) {
    setStatus(error.message, "error");
  }
});

document.querySelectorAll(".mode").forEach((button) => {
  button.addEventListener("click", () => {
    activeMode = button.dataset.mode;
    document.querySelectorAll(".mode").forEach((item) => item.classList.toggle("active", item === button));
    draw();
  });
});

function tick() {
  if (!video.paused && !video.ended) {
    const target = Math.min(detections.length, Math.floor(video.currentTime * FPS) + 1);
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
  video.currentTime = Math.max(0, (target - 1) / FPS);
  processUntil(target);
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
  video.currentTime = target === 0 ? 0 : (target - 1) / FPS;
  try {
    processUntil(target);
  } catch (error) {
    setStatus(error.message, "error");
  }
});

downloadButton.addEventListener("click", () => {
  const text = results
    .map((result) =>
      JSON.stringify({
        frame: result.tracking.frame,
        tracks: result.tracking.tracks,
        lost: result.tracking.lost,
        removed: result.tracking.removed,
        analytics: result.analytics,
      }),
    )
    .join("\n");
  const url = URL.createObjectURL(new Blob([`${text}\n`], { type: "application/x-ndjson" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = "mbmot-events.ndjson";
  link.click();
  URL.revokeObjectURL(url);
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
  createSession();
  processUntil(0);
  setStatus("已载入本地录像，请继续选择匹配的检测流");
});

detectionFile.addEventListener("change", async () => {
  const [file] = detectionFile.files;
  if (!file) return;
  try {
    detections = parseNdjson(await file.text());
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
    rules = defaultRules(canvas.width, canvas.height);
    createSession();
    processUntil(0);
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
