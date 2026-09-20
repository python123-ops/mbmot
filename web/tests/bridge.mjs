import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const modulePath = resolve(process.argv[2] || "_build/site/mbmot.js");
const bridge = await import(pathToFileURL(modulePath));
const setup = JSON.stringify({
  config: { anchor: "bottom_center", stable_frames: 1 },
  lines: [{ id: 1, start: [5, 0], end: [5, 10] }],
  regions: [{ id: 1, vertices: [[0, 0], [10, 0], [10, 10], [0, 10]] }],
});

const created = JSON.parse(bridge.mbmot_create(setup));
assert.equal(created.ok, true);
const id = created.result.session_id;
const frame = JSON.stringify({
  frame: 1,
  detections: [{ xyxy: [1, 1, 3, 5], score: 0.9, class_id: 0 }],
});
const output = JSON.parse(bridge.mbmot_update(id, frame));
assert.equal(output.ok, true);
assert.equal(output.result.tracking.tracks[0].track_id, 1);
assert.equal(output.result.analytics.region_counts[0].current_occupancy, 1);

const rejected = JSON.parse(bridge.mbmot_update(id, frame));
assert.equal(rejected.ok, false);
assert.equal(rejected.code, "invalid_frame");
const resumed = JSON.parse(
  bridge.mbmot_update(id, JSON.stringify({ frame: 2, detections: [] })),
);
assert.equal(resumed.ok, true);

assert.equal(JSON.parse(bridge.mbmot_reset(id)).ok, true);
const afterReset = JSON.parse(bridge.mbmot_update(id, frame));
assert.equal(afterReset.result.tracking.tracks[0].track_id, 1);
assert.equal(JSON.parse(bridge.mbmot_close(id)).ok, true);
assert.equal(JSON.parse(bridge.mbmot_update(id, frame)).code, "unknown_session");

console.log("browser bridge integration passed");
