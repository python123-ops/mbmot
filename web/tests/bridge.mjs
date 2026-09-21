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
assert.equal(output.result.analytics.line_class_counts[0].class_id, 0);
assert.equal(output.result.analytics.region_class_counts[0].class_id, 0);
assert.equal(
  output.result.analytics.region_class_counts[0].current_occupancy,
  1,
);

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

const filteredSetup = JSON.stringify({
  config: { anchor: "bottom_center", stable_frames: 1 },
  lines: [],
  regions: [{
    id: 2,
    vertices: [[0, 0], [10, 0], [10, 10], [0, 10]],
    class_ids: [1],
  }],
});
const filteredCreated = JSON.parse(bridge.mbmot_create(filteredSetup));
assert.equal(filteredCreated.ok, true);
const filteredId = filteredCreated.result.session_id;
const filteredOutput = JSON.parse(bridge.mbmot_update(filteredId, frame));
assert.equal(filteredOutput.ok, true);
assert.equal(filteredOutput.result.analytics.events.length, 0);
assert.equal(filteredOutput.result.analytics.region_class_counts.length, 0);
assert.equal(
  filteredOutput.result.analytics.region_counts[0].current_occupancy,
  0,
);
assert.equal(JSON.parse(bridge.mbmot_close(filteredId)).ok, true);

const invalidFilter = JSON.parse(bridge.mbmot_create(JSON.stringify({
  config: { anchor: "bottom_center", stable_frames: 1 },
  lines: [{ id: 3, start: [0, 0], end: [1, 0], class_ids: [] }],
  regions: [],
})));
assert.equal(invalidFilter.ok, false);
assert.equal(invalidFilter.code, "invalid_config");
assert.match(invalidFilter.message, /class_ids must not be empty/);

console.log("browser bridge integration passed");
