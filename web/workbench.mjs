export function defaultRules(width, height) {
  return {
    lines: [{ id: 1, start: [width * 0.5, height * 0.05], end: [width * 0.5, height * 0.95] }],
    regions: [{ id: 1, vertices: [
      [width * 0.1, height * 0.25],
      [width * 0.9, height * 0.25],
      [width * 0.9, height * 0.95],
      [width * 0.1, height * 0.95],
    ] }],
  };
}

export function cloneRules(rules) {
  return structuredClone(rules);
}

export function addRule(rules, kind, width, height) {
  const next = cloneRules(rules);
  const collection = kind === "line" ? next.lines : next.regions;
  const id = Math.max(0, ...collection.map((rule) => rule.id)) + 1;
  const offset = ((id - 1) % 5) * width * 0.025;
  if (kind === "line") {
    collection.push({ id, start: [width * 0.5 + offset, height * 0.05], end: [width * 0.5 + offset, height * 0.95] });
  } else if (kind === "region") {
    collection.push({ id, vertices: [
      [width * 0.1 + offset, height * 0.25],
      [width * 0.8 + offset, height * 0.25],
      [width * 0.8 + offset, height * 0.85],
      [width * 0.1 + offset, height * 0.85],
    ] });
  } else {
    throw new Error("未知规则类型");
  }
  return { rules: next, id };
}

export function removeRule(rules, kind, id) {
  const next = cloneRules(rules);
  const key = kind === "line" ? "lines" : "regions";
  if (kind !== "line" && kind !== "region") throw new Error("未知规则类型");
  if (!next[key].some((rule) => rule.id === id)) throw new Error("规则不存在");
  next[key] = next[key].filter((rule) => rule.id !== id);
  return next;
}

export function movePoint(rules, kind, id, index, point, width, height) {
  if (!point.every(Number.isFinite) || point[0] < 0 || point[0] > width || point[1] < 0 || point[1] > height) {
    throw new Error("规则坐标超出画面");
  }
  const next = cloneRules(rules);
  const rule = (kind === "line" ? next.lines : next.regions).find((item) => item.id === id);
  if (!rule) throw new Error("规则不存在");
  const points = kind === "line" ? [rule.start, rule.end] : rule.vertices;
  if (!Number.isInteger(index) || index < 0 || index >= points.length) throw new Error("顶点不存在");
  points[index] = point;
  if (kind === "line") [rule.start, rule.end] = points;
  return next;
}

export function setupJson(rules) {
  return JSON.stringify({
    config: { anchor: "bottom_center", stable_frames: 2 },
    lines: rules.lines,
    regions: rules.regions,
  });
}

export function summaryCounts(analytics) {
  const sum = (rows, key) => rows.reduce((total, row) => total + row[key], 0);
  return {
    occupancy: sum(analytics.region_counts, "current_occupancy"),
    left_to_right: sum(analytics.line_counts, "left_to_right"),
    right_to_left: sum(analytics.line_counts, "right_to_left"),
    entries: sum(analytics.region_counts, "entries"),
    unique_region_tracks: sum(analytics.region_counts, "unique_tracks"),
  };
}

export function buildRunReport(detections, results, rules, source) {
  const classes = [...new Set(detections.flatMap((frame) => frame.detections.map((item) => item.class_id)))].sort((a, b) => a - b);
  const final = results.at(-1) || null;
  return {
    format: "mbmot-run-report/1",
    input: {
      name: source.name,
      format: source.format,
      frame_count: detections.length,
      processed_frame_count: results.length,
      detection_count: detections.reduce((count, frame) => count + frame.detections.length, 0),
      replay_sha256: source.replay_sha256 || null,
      class_ids: classes,
      width: source.width,
      height: source.height,
    },
    rules: JSON.parse(setupJson(rules)),
    frames: results.map((result) => ({
      frame: result.tracking.frame,
      tracks: result.tracking.tracks,
      lost: result.tracking.lost,
      removed: result.tracking.removed,
      analytics: result.analytics,
    })),
    final: final ? {
      frame: final.tracking.frame,
      visible_tracks: final.tracking.tracks.length,
      line_counts: final.analytics.line_counts,
      region_counts: final.analytics.region_counts,
      transition_counts: final.analytics.transition_counts,
      summary: summaryCounts(final.analytics),
    } : null,
  };
}
