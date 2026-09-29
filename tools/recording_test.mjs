import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const moon = process.env.MBMOT_MOON || "moon";
const bridge = await import(pathToFileURL(resolve(process.argv[2] || "_build/site/mbmot.js")));
const setup = readFileSync("examples/recording.rules.json", "utf8").trim();
const source = readFileSync("web/assets/detections.ndjson", "utf8");
const detections = source.trim().split(/\r?\n/).map(JSON.parse);
assert.equal(detections.length, 90);
for (const [index, frame] of detections.entries()) {
  assert.equal(frame.frame, index + 1);
  assert.ok(Array.isArray(frame.detections));
}

function replay(input) {
  const run = spawnSync(
    moon,
    ["run", "src/observe", "--target", "native", "--", "examples/recording.rules.json", "--input", "xyxy"],
    { input, encoding: "utf8" },
  );
  if (run.error) throw run.error;
  return run;
}

const native = replay(source);
assert.equal(native.status, 0, native.stderr);
const nativeFrames = native.stdout.trim().split(/\r?\n/).map(JSON.parse);
assert.equal(nativeFrames.length, detections.length);

const created = JSON.parse(bridge.mbmot_create(setup));
assert.equal(created.ok, true, created.message);
const sessionId = created.result.session_id;
const priorEntries = new Map([[1, 0], [2, 0]]);
let priorLeft = 0;
let priorRight = 0;
for (const [index, detection] of detections.entries()) {
  if (index === 46) {
    const invalidFrame = {
      ...detection,
      detections: [{ xyxy: [10, 10, 10, 20], score: 0.9, class_id: 0 }],
    };
    const invalid = JSON.parse(bridge.mbmot_update(sessionId, JSON.stringify(invalidFrame)));
    assert.equal(invalid.ok, false);
    assert.equal(invalid.code, "invalid_frame");
  }
  const updated = JSON.parse(bridge.mbmot_update(sessionId, JSON.stringify(detection)));
  assert.equal(updated.ok, true, `frame ${detection.frame}: ${updated.message}`);
  assert.deepEqual(updated.result, nativeFrames[index], `native/browser frame ${detection.frame}`);

  const { tracking, analytics } = updated.result;
  assert.equal(tracking.frame, detection.frame);
  assert.equal(analytics.frame, detection.frame);
  const visible = tracking.tracks.map((track) => track.track_id);
  assert.deepEqual(visible, [...visible].sort((left, right) => left - right));
  assert.equal(new Set([...visible, ...tracking.lost, ...tracking.removed]).size,
    visible.length + tracking.lost.length + tracking.removed.length);
  for (const track of tracking.tracks) {
    assert.equal(track.class_id, 0);
    assert.ok(track.first_frame <= track.last_frame && track.last_frame === detection.frame);
    assert.ok(track.hits >= 1 && track.score >= 0 && track.score <= 1);
    assert.ok(track.xyxy.every(Number.isFinite));
  }
  const line = analytics.line_counts[0];
  assert.ok(line.left_to_right >= priorLeft && line.right_to_left >= priorRight);
  assert.deepEqual(analytics.region_counts.map((region) => region.region_id), [1, 2]);
  for (const region of analytics.region_counts) {
    assert.ok(region.entries >= priorEntries.get(region.region_id));
    assert.ok(region.exits <= region.entries);
    assert.ok(region.peak_occupancy >= region.current_occupancy);
    assert.equal(region.current_occupancy,
      analytics.occupants.filter((occupant) => occupant.region_id === region.region_id).length);
    priorEntries.set(region.region_id, region.entries);
  }
  priorLeft = line.left_to_right;
  priorRight = line.right_to_left;
}

const rejected = replay(`${detections.slice(0, 46).map(JSON.stringify).join("\n")}\n${JSON.stringify({
  ...detections[46], detections: [{ xyxy: [10, 10, 10, 20], score: 0.9, class_id: 0 }],
})}\n`);
assert.notEqual(rejected.status, 0);
assert.equal(rejected.stdout.trim().split(/\r?\n/).length, 46);
assert.deepEqual(rejected.stdout.trim().split(/\r?\n/).map(JSON.parse), nativeFrames.slice(0, 46));
assert.match(rejected.stderr, /input line 47 \(tracking\): invalid detection/);

const final = nativeFrames.at(-1).analytics;
assert.deepEqual(final.line_counts[0], {
  line_id: 1, left_to_right: 1, right_to_left: 0,
  unique_left_to_right: 1, unique_right_to_left: 0,
});
assert.deepEqual(final.region_counts[1], {
  region_id: 2, entries: 3, exits: 2, unique_tracks: 1,
  current_occupancy: 1, peak_occupancy: 1, completed_dwell_frames: 67,
});

assert.equal(JSON.parse(bridge.mbmot_reset(sessionId)).ok, true);
for (const [index, detection] of detections.slice(0, 10).entries()) {
  const replayed = JSON.parse(bridge.mbmot_update(sessionId, JSON.stringify(detection)));
  assert.equal(replayed.ok, true);
  assert.deepEqual(replayed.result, nativeFrames[index]);
}
assert.equal(JSON.parse(bridge.mbmot_close(sessionId)).ok, true);
console.log("90 recorded frames: native/browser results, bad-frame recovery, and reset passed");
