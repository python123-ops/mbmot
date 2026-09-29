from __future__ import annotations

import json
import math
import os
import subprocess
import sys
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

from pipeline import (
    PipelineError,
    analyze_tracks,
    convert_yolo_frames,
    load_analytics_setup,
    read_ndjson,
    track_detections,
    write_ndjson,
)
from video_io import validate_external_frames
from video_demo import _validate_arguments


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

    def test_external_frames_reject_boolean_and_fractional_ids(self) -> None:
        for frame in (True, 1.0, 0, 2):
            with self.subTest(frame=frame):
                with self.assertRaisesRegex(PipelineError, "consecutive frames"):
                    validate_external_frames([{"frame": frame, "detections": []}])

    def test_external_frames_require_a_detection_array(self) -> None:
        with self.assertRaisesRegex(PipelineError, "needs detections array"):
            validate_external_frames([{"frame": 1, "detections": None}])

    def test_yolo_cli_options_require_external_yolo_detections(self) -> None:
        options = Namespace(
            detections_format="yolo",
            detections=None,
            classes=None,
            confidence=0.55,
            nms_threshold=0.4,
            max_frames=None,
        )
        with self.assertRaisesRegex(PipelineError, "requires --detections"):
            _validate_arguments(options)
        options.detections_format = "xyxy"
        options.classes = "[0]"
        with self.assertRaisesRegex(PipelineError, "only to YOLO"):
            _validate_arguments(options)


class MoonBitBridgeTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get("MBMOT_TEST_MOON"), "MoonBit bridge test not requested")
    def test_yolo_video_dimensions_and_moonbit_validation(self) -> None:
        repository = Path(__file__).resolve().parents[2]
        moon = os.environ["MBMOT_TEST_MOON"]
        normalized = {
            "frame": 1,
            "width": 100,
            "height": 50,
            "coordinates": "normalized",
            "detections": [
                {"cxcywh": [0.5, 0.5, 0.4, 0.4], "score": 0.9, "class_id": 2}
            ],
        }
        pixels = {
            **normalized,
            "frame": 2,
            "coordinates": "pixels",
            "detections": [
                {"cxcywh": [50, 25, 40, 20], "score": 0.9, "class_id": 2}
            ],
        }
        converted = convert_yolo_frames([normalized, pixels], 100, 50, repository, moon)
        self.assertEqual(converted[0]["detections"], converted[1]["detections"])
        self.assertEqual(converted[0]["detections"][0]["xyxy"], [30, 15, 70, 35])

        mixed_classes = {
            **normalized,
            "detections": [
                *normalized["detections"],
                {"cxcywh": [0.2, 0.2, 0.1, 0.1], "score": 0.8, "class_id": 1},
            ],
        }
        selected = convert_yolo_frames(
            [mixed_classes], 100, 50, repository, moon, classes="[2]"
        )
        self.assertEqual(selected[0]["detections"], converted[0]["detections"])
        with self.assertRaisesRegex(PipelineError, "duplicate class_id"):
            convert_yolo_frames(
                [normalized], 100, 50, repository, moon, classes="[2,2]"
            )

        for invalid_width, invalid_height in (
            (101, 50),
            (100.0, 50),
            (True, 50),
            (100, 51),
            (100, None),
        ):
            with self.subTest(width=invalid_width, height=invalid_height):
                with self.assertRaisesRegex(PipelineError, "row 1 dimensions"):
                    convert_yolo_frames(
                        [{**normalized, "width": invalid_width, "height": invalid_height}],
                        100,
                        50,
                        repository,
                        moon,
                    )

        invalid_box = {
            **pixels,
            "coordinates": "normalized",
            "detections": [
                {"cxcywh": [0.9, 0.5, 0.4, 0.2], "score": 0.9, "class_id": 2}
            ],
        }
        with self.assertRaisesRegex(PipelineError, "src/yolo_import failed: line 2"):
            convert_yolo_frames([normalized, invalid_box], 100, 50, repository, moon)

        hidden_invalid = {
            **normalized,
            "detections": [
                *normalized["detections"],
                {"cxcywh": [0.2, 0.2, 0.0, 0.1], "score": 0.8, "class_id": 1},
            ],
        }
        with self.assertRaisesRegex(PipelineError, "invalid detection 1"):
            convert_yolo_frames(
                [hidden_invalid], 100, 50, repository, moon, classes="[2]"
            )

    @unittest.skipUnless(os.environ.get("MBMOT_TEST_MOON"), "MoonBit bridge test not requested")
    def test_bad_video_dimensions_leave_no_rendered_output(self) -> None:
        repository = Path(__file__).resolve().parents[2]
        video = repository / "web" / "assets" / "demo.mp4"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            input_path = root / "wrong-size.ndjson"
            output_path = root / "annotated.mp4"
            write_ndjson(
                input_path,
                [
                    {
                        "frame": 1,
                        "width": 1,
                        "height": 1,
                        "coordinates": "pixels",
                        "detections": [],
                    }
                ],
            )
            completed = subprocess.run(
                [
                    sys.executable,
                    str(repository / "tools" / "video_demo" / "video_demo.py"),
                    "--source", str(video),
                    "--output", str(output_path),
                    "--config", str(repository / "examples" / "video-demo-config.json"),
                    "--detections", str(input_path),
                    "--detections-format", "yolo",
                    "--max-frames", "1",
                    "--moon", os.environ["MBMOT_TEST_MOON"],
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
                check=False,
            )
            self.assertEqual(completed.returncode, 2)
            self.assertIn("row 1 dimensions do not match video", completed.stderr)
            self.assertFalse(output_path.exists())
            self.assertFalse((root / "annotated-artifacts").exists())

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

    @unittest.skipUnless(os.environ.get("MBMOT_TEST_MOON"), "MoonBit bridge test not requested")
    def test_recorded_video_accepts_mixed_yolo_coordinate_modes(self) -> None:
        import cv2

        repository = Path(__file__).resolve().parents[2]
        moon = os.environ["MBMOT_TEST_MOON"]
        video = repository / "web" / "assets" / "demo.mp4"
        capture = cv2.VideoCapture(str(video))
        self.assertTrue(capture.isOpened())
        width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
        capture.release()
        frame_count = 90 if os.environ.get("MBMOT_FULL_VIDEO_TEST") == "1" else 12
        all_original = read_ndjson(repository / "web" / "assets" / "detections.ndjson")
        original = all_original[:frame_count]
        yolo = []
        for row in all_original:
            normalized = row["frame"] % 2 == 0
            detections = []
            for item in row["detections"]:
                x1, y1, x2, y2 = item["xyxy"]
                center_box = [(x1 + x2) / 2, (y1 + y2) / 2, x2 - x1, y2 - y1]
                if normalized:
                    center_box = [
                        center_box[0] / width,
                        center_box[1] / height,
                        center_box[2] / width,
                        center_box[3] / height,
                    ]
                detections.append(
                    {"cxcywh": center_box, "score": item["score"], "class_id": item["class_id"]}
                )
            yolo.append(
                {
                    "frame": row["frame"],
                    "width": width,
                    "height": height,
                    "coordinates": "normalized" if normalized else "pixels",
                    "detections": detections,
                }
            )

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            input_path = root / "detections.yolo.ndjson"
            output_path = root / "annotated.mp4"
            artifacts = root / "intermediate"
            write_ndjson(input_path, yolo)
            completed = subprocess.run(
                [
                    sys.executable,
                    str(repository / "tools" / "video_demo" / "video_demo.py"),
                    "--source", str(video),
                    "--output", str(output_path),
                    "--config", str(repository / "examples" / "video-demo-config.json"),
                    "--detections", str(input_path),
                    "--detections-format", "yolo",
                    "--classes", "[0]",
                    "--max-frames", str(frame_count),
                    "--artifacts", str(artifacts),
                    "--moon", moon,
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            converted = read_ndjson(artifacts / "detections.ndjson")
            tracked = read_ndjson(artifacts / "tracks.ndjson")
            analytics = read_ndjson(artifacts / "analytics.ndjson")
            self.assertEqual(
                (len(converted), len(tracked), len(analytics)),
                (frame_count, frame_count, frame_count),
            )
            for expected, actual in zip(original, converted):
                self.assertEqual(expected["frame"], actual["frame"])
                self.assertEqual(len(expected["detections"]), len(actual["detections"]))
                for left, right in zip(expected["detections"], actual["detections"]):
                    self.assertEqual(left["class_id"], right["class_id"])
                    self.assertEqual(left["score"], right["score"])
                    for left_coord, right_coord in zip(left["xyxy"], right["xyxy"]):
                        self.assertTrue(math.isclose(left_coord, right_coord, abs_tol=1e-9))
            direct = track_detections(original, repository, moon=moon)
            for expected, actual in zip(direct, tracked):
                self.assertEqual(expected["frame"], actual["frame"])
                self.assertEqual(expected["lost"], actual["lost"])
                self.assertEqual(expected["removed"], actual["removed"])
                self.assertEqual(
                    [item["track_id"] for item in expected["tracks"]],
                    [item["track_id"] for item in actual["tracks"]],
                )
            setup = json.loads((artifacts / "analytics-config.json").read_text(encoding="utf-8"))
            self.assertEqual(analytics, analyze_tracks(setup, direct, repository, moon=moon))
            self.assertEqual(analytics[-1]["frame"], frame_count)
            rendered = cv2.VideoCapture(str(output_path))
            self.assertTrue(rendered.isOpened())
            self.assertEqual(int(rendered.get(cv2.CAP_PROP_FRAME_COUNT)), frame_count)
            rendered.release()


if __name__ == "__main__":
    unittest.main()
