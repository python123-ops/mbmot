"""Video capture and output helpers for file and camera demo sources."""

from __future__ import annotations

import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, List, Optional, Protocol, Sequence, Tuple

from detector import load_opencv
from pipeline import PipelineError


class FrameDetector(Protocol):
    def detect(self, frame: Any) -> List[dict]:
        ...


@dataclass(frozen=True)
class VideoInfo:
    path: Path
    width: int
    height: int
    fps: float
    frames: int


def open_video_writer(
    cv2: Any, path: Path, fps: float, size: Tuple[int, int]
):
    path.parent.mkdir(parents=True, exist_ok=True)
    writer = cv2.VideoWriter(
        str(path), cv2.VideoWriter_fourcc(*"mp4v"), fps, size
    )
    if not writer.isOpened():
        raise PipelineError(f"cannot create output video: {path.name}")
    return writer


def validate_external_frames(rows: Sequence[dict]) -> None:
    for index, row in enumerate(rows, start=1):
        if row.get("frame") != index:
            raise PipelineError(
                f"external detections must contain consecutive frames from 1; row {index} differs"
            )
        if not isinstance(row.get("detections"), list):
            raise PipelineError(f"external detection row {index} needs detections array")


def _source_value(text: str) -> Any:
    if text.isdecimal():
        return int(text)
    return text


def collect_detections(
    source: str,
    detector: Optional[FrameDetector],
    external: Optional[Sequence[dict]],
    max_frames: Optional[int],
    camera_copy: Optional[Path],
) -> Tuple[VideoInfo, List[dict]]:
    cv2 = load_opencv()
    source_value = _source_value(source)
    is_camera = isinstance(source_value, int)
    if is_camera and external is not None:
        raise PipelineError("precomputed detections cannot be paired with a live camera")
    if is_camera and max_frames is None:
        raise PipelineError("camera input requires --max-frames")
    capture = cv2.VideoCapture(source_value)
    if not capture.isOpened():
        raise PipelineError(f"cannot open video source: {source}")
    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = float(capture.get(cv2.CAP_PROP_FPS))
    if width <= 0 or height <= 0:
        capture.release()
        raise PipelineError("video source did not report valid dimensions")
    if not math.isfinite(fps) or fps <= 0:
        fps = 25.0
    raw_writer = None
    if is_camera:
        if camera_copy is None:
            capture.release()
            raise PipelineError("camera capture needs a temporary recording path")
        raw_writer = open_video_writer(cv2, camera_copy, fps, (width, height))
    rows: List[dict] = []
    frame_id = 0
    try:
        while max_frames is None or frame_id < max_frames:
            ok, frame = capture.read()
            if not ok:
                break
            frame_id += 1
            if raw_writer is not None:
                raw_writer.write(frame)
            if external is not None:
                if frame_id > len(external):
                    raise PipelineError("video contains more frames than external detections")
                rows.append(dict(external[frame_id - 1]))
            else:
                if detector is None:
                    raise PipelineError("no detector was configured")
                rows.append({"frame": frame_id, "detections": detector.detect(frame)})
            if frame_id % 30 == 0:
                print(f"read {frame_id} frames", file=sys.stderr)
    finally:
        capture.release()
        if raw_writer is not None:
            raw_writer.release()
    if frame_id == 0:
        raise PipelineError("video source contains no readable frames")
    if external is not None and frame_id < len(external):
        if max_frames is None or frame_id < max_frames:
            raise PipelineError("external detections contain more frames than the video")
        rows = rows[:frame_id]
    render_path = camera_copy if is_camera else Path(source)
    if render_path is None:
        raise PipelineError("camera recording was not created")
    return VideoInfo(render_path, width, height, fps, frame_id), rows
