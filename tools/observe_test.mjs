import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";

const moon = process.env.MBMOT_MOON || "moon";
const source = readFileSync("examples/observe.yolo.ndjson", "utf8");
const expected = readFileSync("examples/observe.expected.ndjson", "utf8");
const xyxy = readFileSync("examples/observe.xyxy.ndjson", "utf8");
const rules = "examples/observe.rules.json";

function observe(input, args = [rules]) {
  const run = spawnSync(moon, ["run", "src/observe", "--target", "native", "--", ...args], {
    input,
    encoding: "utf8",
  });
  if (run.error) throw run.error;
  return run;
}

const complete = observe(source);
assert.equal(complete.status, 0, complete.stderr);
assert.equal(complete.stdout.replaceAll("\r\n", "\n"), expected.replaceAll("\r\n", "\n"));
const frames = complete.stdout.trim().split(/\r?\n/).map(JSON.parse);
assert.equal(frames.length, 7);
assert.deepEqual(frames[3].tracking.lost, [1]);
assert.equal(frames[4].tracking.tracks[0].track_id, 1);
assert.equal(frames[6].analytics.region_counts[0].completed_dwell_frames, 6);

const direct = observe(xyxy, [rules, "--input", "xyxy"]);
assert.equal(direct.status, 0, direct.stderr);
assert.equal(direct.stdout.replaceAll("\r\n", "\n"), expected.replaceAll("\r\n", "\n"));
const empty = observe("");
assert.equal(empty.status, 0, empty.stderr);
assert.equal(empty.stdout, "");

const filtered = observe(source, [rules, "--classes", "[1]"]);
assert.equal(filtered.status, 0, filtered.stderr);
for (const line of filtered.stdout.trim().split(/\r?\n/)) {
  const frame = JSON.parse(line);
  assert.deepEqual(frame.tracking.tracks, []);
  assert.equal(frame.analytics.region_counts[0].entries, 0);
}

const first = source.split(/\r?\n/)[0];
const malformed = observe(`${first}\n{"frame":2,"width":0,"height":10,"coordinates":"pixels","detections":[]}\n`);
assert.notEqual(malformed.status, 0);
assert.equal(malformed.stdout.trim(), expected.split(/\r?\n/)[0]);
assert.match(malformed.stderr, /input line 2: invalid frame:/);

const repeated = observe(`${first}\n${first}\n`);
assert.notEqual(repeated.status, 0);
assert.equal(repeated.stdout.trim(), expected.split(/\r?\n/)[0]);
assert.match(repeated.stderr, /input line 2: frame must increase/);

const firstDirect = xyxy.split(/\r?\n/)[0];
const repeatedDirect = observe(`${firstDirect}\n${firstDirect}\n`, [rules, "--input", "xyxy"]);
assert.notEqual(repeatedDirect.status, 0);
assert.equal(repeatedDirect.stdout.trim(), expected.split(/\r?\n/)[0]);
assert.match(repeatedDirect.stderr, /input line 2 \(tracking\): frame must increase/);

const misplacedFilter = observe(xyxy, [rules, "--input", "xyxy", "--classes", "[0]"]);
assert.notEqual(misplacedFilter.status, 0);
assert.equal(misplacedFilter.stdout, "");
assert.match(misplacedFilter.stderr, /--classes applies only to yolo input/);

const invalidRules = observe(first, ["examples/observe.yolo.ndjson"]);
assert.notEqual(invalidRules.status, 0);
assert.equal(invalidRules.stdout, "");
assert.match(invalidRules.stderr, /rules: invalid JSON:/);

console.log("one-command detector-to-events replay passed");
