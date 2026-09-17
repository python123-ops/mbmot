"""Deterministic file bridge between video detections and MoonBit MBMOT tools."""

from __future__ import annotations

import json
import math
import subprocess
from pathlib import Path
from typing import Any, Iterable, List, Mapping, Sequence


JsonObject = Mapping[str, Any]


class PipelineError(RuntimeError):
    """Raised when demo input or a MoonBit subprocess violates the pipeline."""


def compact_json(value: JsonObject) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def read_ndjson(path: Path) -> List[dict]:
    rows: List[dict] = []
    with path.open("r", encoding="utf-8") as stream:
        for line_number, raw in enumerate(stream, start=1):
            text = raw.strip()
            if not text:
                continue
            try:
                value = json.loads(text)
            except json.JSONDecodeError as error:
                raise PipelineError(
                    f"{path.name} line {line_number}: invalid JSON: {error.msg}"
                ) from error
            if not isinstance(value, dict):
                raise PipelineError(
                    f"{path.name} line {line_number}: expected a JSON object"
                )
            rows.append(value)
    return rows


def write_ndjson(path: Path, rows: Iterable[JsonObject]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        for row in rows:
            stream.write(compact_json(row))
            stream.write("\n")


def _number(value: Any, context: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise PipelineError(f"{context} must be a finite number")
    result = float(value)
    if not math.isfinite(result):
        raise PipelineError(f"{context} must be a finite number")
    return result


def _point(value: Any, context: str, coordinates: str, width: int, height: int) -> list:
    if not isinstance(value, list) or len(value) != 2:
        raise PipelineError(f"{context} must contain exactly two numbers")
    x = _number(value[0], f"{context}[0]")
    y = _number(value[1], f"{context}[1]")
    if coordinates == "normalized":
        if not 0.0 <= x <= 1.0 or not 0.0 <= y <= 1.0:
            raise PipelineError(f"{context} normalized coordinates must be in [0, 1]")
        return [x * width, y * height]
    return [x, y]


def load_analytics_setup(path: Path, width: int, height: int) -> dict:
    if width <= 0 or height <= 0:
        raise PipelineError("video dimensions must be positive")
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise PipelineError(f"cannot read analytics config: {error}") from error
    except json.JSONDecodeError as error:
        raise PipelineError(f"analytics config is invalid JSON: {error.msg}") from error
    if not isinstance(raw, dict):
        raise PipelineError("analytics config must be a JSON object")
    coordinates = raw.get("coordinates", "normalized")
    if coordinates not in ("normalized", "pixels"):
        raise PipelineError("coordinates must be normalized or pixels")
    anchor = raw.get("anchor", "bottom_center")
    if anchor not in ("center", "bottom_center"):
        raise PipelineError("anchor must be center or bottom_center")
    stable_frames = raw.get("stable_frames", 2)
    if isinstance(stable_frames, bool) or not isinstance(stable_frames, int):
        raise PipelineError("stable_frames must be an integer")
    if stable_frames < 1:
        raise PipelineError("stable_frames must be at least 1")
    raw_lines = raw.get("lines", [])
    raw_regions = raw.get("regions", [])
    if not isinstance(raw_lines, list) or not isinstance(raw_regions, list):
        raise PipelineError("lines and regions must be arrays")
    lines = []
    for index, line in enumerate(raw_lines):
        if not isinstance(line, dict):
            raise PipelineError(f"line {index} must be an object")
        lines.append(
            {
                "id": line.get("id"),
                "start": _point(
                    line.get("start"), f"line {index} start", coordinates, width, height
                ),
                "end": _point(
                    line.get("end"), f"line {index} end", coordinates, width, height
                ),
            }
        )
    regions = []
    for index, region in enumerate(raw_regions):
        if not isinstance(region, dict):
            raise PipelineError(f"region {index} must be an object")
        vertices = region.get("vertices")
        if not isinstance(vertices, list):
            raise PipelineError(f"region {index} vertices must be an array")
        regions.append(
            {
                "id": region.get("id"),
                "vertices": [
                    _point(
                        point,
                        f"region {index} vertex {vertex_index}",
                        coordinates,
                        width,
                        height,
                    )
                    for vertex_index, point in enumerate(vertices)
                ],
            }
        )
    return {
        "config": {"anchor": anchor, "stable_frames": stable_frames},
        "lines": lines,
        "regions": regions,
    }


def _parse_process_output(package: str, output: str) -> List[dict]:
    rows: List[dict] = []
    for line_number, raw in enumerate(output.splitlines(), start=1):
        text = raw.strip()
        if not text:
            continue
        try:
            value = json.loads(text)
        except json.JSONDecodeError as error:
            raise PipelineError(
                f"{package} output line {line_number} is not JSON: {error.msg}"
            ) from error
        if not isinstance(value, dict):
            raise PipelineError(f"{package} output line {line_number} is not an object")
        rows.append(value)
    return rows


def run_moon_package(
    package: str,
    rows: Sequence[JsonObject],
    repository: Path,
    moon: str = "moon",
    timeout: int = 600,
) -> List[dict]:
    payload = "".join(compact_json(row) + "\n" for row in rows)
    try:
        completed = subprocess.run(
            [moon, "run", package, "--target", "native"],
            cwd=str(repository),
            input=payload,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            timeout=timeout,
            check=False,
        )
    except OSError as error:
        raise PipelineError(f"cannot start MoonBit command: {error}") from error
    except subprocess.TimeoutExpired as error:
        raise PipelineError(f"{package} did not finish within {timeout} seconds") from error
    if completed.returncode != 0:
        reason = completed.stderr.strip() or f"exit code {completed.returncode}"
        raise PipelineError(f"{package} failed: {reason}")
    return _parse_process_output(package, completed.stdout)


def _validate_frames(rows: Sequence[JsonObject], label: str) -> None:
    previous = 0
    for index, row in enumerate(rows):
        frame = row.get("frame")
        if isinstance(frame, bool) or not isinstance(frame, int):
            raise PipelineError(f"{label} row {index + 1} has no integer frame")
        if frame <= previous:
            raise PipelineError(f"{label} frames must be strictly increasing")
        previous = frame


def track_detections(
    detection_frames: Sequence[JsonObject],
    repository: Path,
    moon: str = "moon",
) -> List[dict]:
    _validate_frames(detection_frames, "detection")
    tracked = run_moon_package("src/replay", detection_frames, repository, moon=moon)
    if len(tracked) != len(detection_frames):
        raise PipelineError(
            f"tracker returned {len(tracked)} frames for {len(detection_frames)} inputs"
        )
    for expected, actual in zip(detection_frames, tracked):
        if expected["frame"] != actual.get("frame"):
            raise PipelineError("tracker output frame does not match its input")
    return tracked


def analyze_tracks(
    setup: JsonObject,
    track_frames: Sequence[JsonObject],
    repository: Path,
    moon: str = "moon",
) -> List[dict]:
    _validate_frames(track_frames, "track")
    analyzed = run_moon_package(
        "src/analytics_replay", [setup, *track_frames], repository, moon=moon
    )
    if len(analyzed) != len(track_frames):
        raise PipelineError(
            f"analytics returned {len(analyzed)} frames for {len(track_frames)} inputs"
        )
    for expected, actual in zip(track_frames, analyzed):
        if expected["frame"] != actual.get("frame"):
            raise PipelineError("analytics output frame does not match its input")
    return analyzed
