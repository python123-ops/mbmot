import assert from "node:assert/strict";
import { addRule, buildRunReport, defaultRules, movePoint, removeRule, setupJson, summaryCounts } from "../workbench.mjs";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const bridge = await import(pathToFileURL(resolve(process.argv[2] || "_build/site/mbmot.js")));
const original = defaultRules(100, 100);
const secondLine = addRule(original, "line", 100, 100);
const secondRegion = addRule(secondLine.rules, "region", 100, 100);
assert.equal(original.lines.length, 1);
assert.equal(secondLine.rules.lines.length, 2);
assert.equal(secondRegion.rules.regions.length, 2);
assert.equal(secondRegion.rules.regions[1].id, 2);
const movedRegion = movePoint(secondRegion.rules, "region", 2, 0, [15, 25], 100, 100);
assert.deepEqual(movedRegion.regions[1].vertices[0], [15, 25]);
assert.equal(removeRule(movedRegion, "region", 1).regions.length, 1);
const moved = movePoint(secondRegion.rules, "line", 2, 0, [20, 10], 100, 100);
assert.deepEqual(moved.lines[1].start, [20, 10]);
assert.deepEqual(secondRegion.rules.lines[1].start, [52.5, 5]);
assert.equal(removeRule(moved, "line", 1).lines.length, 1);
assert.throws(() => movePoint(moved, "line", 2, 0, [101, 0], 100, 100), /超出画面/);

const session = JSON.parse(bridge.mbmot_create(setupJson(moved)));
assert.equal(session.ok, true);
const id = session.result.session_id;
const detections = [{ frame: 1, detections: [{ xyxy: [10, 20, 20, 30], score: 0.9, class_id: 0 }] }];
const result = JSON.parse(bridge.mbmot_update(id, JSON.stringify(detections[0])));
assert.equal(result.ok, true);
assert.equal(result.result.analytics.line_counts.length, 2);
assert.equal(result.result.analytics.region_counts.length, 2);
const summary = summaryCounts(result.result.analytics);
assert.equal(summary.occupancy, 0);
const report = buildRunReport(detections, [result.result], moved, {
  name: "sample.ndjson", format: "xyxy", width: 100, height: 100,
});
assert.equal(report.input.detection_count, 1);
assert.deepEqual(report.input.class_ids, [0]);
assert.deepEqual(report.rules.lines, moved.lines);
assert.equal(report.frames[0].frame, report.final.frame);
assert.deepEqual(report.frames[0].analytics.line_counts, report.final.line_counts);
assert.deepEqual(report.final.summary, summary);
assert.equal(JSON.parse(bridge.mbmot_close(id)).ok, true);
console.log("workbench rules and report integration passed");
