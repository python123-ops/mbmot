from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from pipeline import (
    PipelineError,
    analyze_tracks,
    load_analytics_setup,
    read_ndjson,
    track_detections,
    write_ndjson,
)


class ConfigTests(unittest.TestCase):
    def _config(self, value: dict) -> Path:
        temporary = tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", encoding="utf-8", delete=False
        )
        self.addCleanup(lambda: Path(temporary.name).unlink(missing_ok=True))
        with temporary:
            json.dump(value, temporary)
        return Path(temporary.name)

    def test_normalized_rules_are_scaled_to_video_pixels(self) -> None:
        config = self._config(
            {
                "coordinates": "normalized",
                "anchor": "bottom_center",
                "stable_frames": 2,
                "lines": [{"id": 4, "start": [0.5, 0], "end": [0.5, 1]}],
                "regions": [
                    {
                        "id": 7,
                        "vertices": [[0.25, 0.25], [0.75, 0.25], [0.75, 1]],
                    }
                ],
            }
        )
        setup = load_analytics_setup(config, 640, 480)
        self.assertEqual(setup["lines"][0]["start"], [320.0, 0.0])
        self.assertEqual(setup["lines"][0]["end"], [320.0, 480.0])
        self.assertEqual(setup["regions"][0]["vertices"][0], [160.0, 120.0])

    def test_pixel_rules_are_not_rescaled(self) -> None:
        config = self._config(
            {
                "coordinates": "pixels",
                "lines": [{"id": 1, "start": [12, 4], "end": [12, 100]}],
                "regions": [],
            }
        )
        setup = load_analytics_setup(config, 1920, 1080)
        self.assertEqual(setup["lines"][0]["start"], [12.0, 4.0])

    def test_out_of_range_normalized_point_is_rejected(self) -> None:
        config = self._config(
            {
                "coordinates": "normalized",
                "lines": [{"id": 1, "start": [-0.1, 0], "end": [1, 1]}],
                "regions": [],
            }
        )
        with self.assertRaisesRegex(PipelineError, "must be in"):
            load_analytics_setup(config, 640, 480)


class NdjsonTests(unittest.TestCase):
    def test_round_trip_preserves_rows_and_ignores_blank_lines(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "stream.ndjson"
            rows = [{"frame": 1, "detections": []}, {"frame": 2, "detections": []}]
            write_ndjson(path, rows)
            with path.open("a", encoding="utf-8") as stream:
                stream.write("\n")
            self.assertEqual(read_ndjson(path), rows)


class MoonBitBridgeTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get("MBMOT_TEST_MOON"), "MoonBit bridge test not requested")
    def test_detector_tracker_analytics_chain(self) -> None:
        repository = Path(__file__).resolve().parents[2]
        moon = os.environ["MBMOT_TEST_MOON"]
        detections = [
            {
                "frame": 1,
                "detections": [
                    {"xyxy": [0, 0, 10, 10], "score": 0.95, "class_id": 0}
                ],
            },
            {
                "frame": 2,
                "detections": [
                    {"xyxy": [1, 0, 11, 10], "score": 0.92, "class_id": 0}
                ],
            },
        ]
        tracked = track_detections(detections, repository, moon=moon)
        self.assertEqual([row["frame"] for row in tracked], [1, 2])
        self.assertEqual(tracked[0]["tracks"][0]["track_id"], 1)
        setup = {
            "config": {"anchor": "bottom_center", "stable_frames": 1},
            "lines": [],
            "regions": [],
        }
        analytics = analyze_tracks(setup, tracked, repository, moon=moon)
        self.assertEqual([row["frame"] for row in analytics], [1, 2])
        self.assertEqual(analytics[0]["events"], [])


if __name__ == "__main__":
    unittest.main()
