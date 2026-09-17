"""Render MBMOT identities and spatial analytics over a recorded video."""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

from detector import HogPersonDetector
from pipeline import (
    PipelineError,
    analyze_tracks,
    load_analytics_setup,
    read_ndjson,
    track_detections,
    write_ndjson,
)
from rendering import render_video
from video_io import collect_detections, validate_external_frames


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a recorded video through MoonBit MBMOT and render its results."
    )
    parser.add_argument("--source", required=True, help="video path or camera index")
    parser.add_argument("--output", required=True, type=Path, help="annotated MP4 path")
    parser.add_argument("--config", required=True, type=Path, help="spatial rules JSON")
    parser.add_argument(
        "--detections",
        type=Path,
        help="detector NDJSON; omit to use OpenCV's built-in person detector",
    )
    parser.add_argument("--confidence", type=float, default=0.55)
    parser.add_argument("--nms-threshold", type=float, default=0.4)
    parser.add_argument("--max-frames", type=int)
    parser.add_argument("--moon", default="moon", help="MoonBit moon executable")
    parser.add_argument("--artifacts", type=Path, help="directory for three NDJSON stages")
    parser.add_argument("--preview", action="store_true")
    return parser.parse_args()


def _validate_arguments(arguments: argparse.Namespace) -> None:
    if not 0.0 <= arguments.confidence <= 1.0:
        raise PipelineError("confidence must be in [0, 1]")
    if not 0.0 <= arguments.nms_threshold <= 1.0:
        raise PipelineError("nms-threshold must be in [0, 1]")
    if arguments.max_frames is not None and arguments.max_frames < 1:
        raise PipelineError("max-frames must be positive")


def main() -> int:
    arguments = _arguments()
    _validate_arguments(arguments)
    repository = Path(__file__).resolve().parents[2]
    external = None
    detector = None
    if arguments.detections is not None:
        external = read_ndjson(arguments.detections)
        validate_external_frames(external)
        if arguments.max_frames is not None:
            external = external[: arguments.max_frames]
    else:
        detector = HogPersonDetector(arguments.confidence, arguments.nms_threshold)
    work_root = repository / ".video-demo-work"
    work_root.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=str(work_root)) as temporary:
        camera_copy = Path(temporary) / "camera.mp4"
        info, detection_frames = collect_detections(
            arguments.source,
            detector,
            external,
            arguments.max_frames,
            camera_copy,
        )
        setup = load_analytics_setup(
            arguments.config, width=info.width, height=info.height
        )
        print("running MoonBit tracker", file=sys.stderr)
        tracked = track_detections(
            detection_frames, repository=repository, moon=arguments.moon
        )
        print("running MoonBit spatial analytics", file=sys.stderr)
        analytics = analyze_tracks(setup, tracked, repository=repository, moon=arguments.moon)
        artifacts = arguments.artifacts
        if artifacts is None:
            artifacts = arguments.output.with_name(arguments.output.stem + "-artifacts")
        write_ndjson(artifacts / "detections.ndjson", detection_frames)
        write_ndjson(artifacts / "tracks.ndjson", tracked)
        write_ndjson(artifacts / "analytics.ndjson", analytics)
        (artifacts / "analytics-config.json").write_text(
            json.dumps(setup, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print("rendering annotated video", file=sys.stderr)
        render_video(
            info,
            arguments.output,
            setup,
            tracked,
            analytics,
            arguments.preview,
        )
    try:
        work_root.rmdir()
    except OSError:
        pass
    print(
        f"wrote {arguments.output} ({info.frames} frames) and {artifacts}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except PipelineError as error:
        print(f"video demo: {error}", file=sys.stderr)
        sys.exit(2)
