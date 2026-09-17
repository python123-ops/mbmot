"""Overlay tracked identities, rules, events, and counters on video frames."""

from __future__ import annotations

from pathlib import Path
from typing import Any, List, Sequence, Tuple

from detector import load_opencv
from pipeline import PipelineError
from video_io import VideoInfo, open_video_writer


def _color(track_id: int) -> Tuple[int, int, int]:
    return (
        64 + (track_id * 67) % 192,
        64 + (track_id * 131) % 192,
        64 + (track_id * 193) % 192,
    )


def _integer_point(point: Sequence[float]) -> Tuple[int, int]:
    return int(round(point[0])), int(round(point[1]))


def _event_text(event: dict) -> str:
    event_type = event.get("type")
    if event_type == "line_crossed":
        direction = "L->R" if event.get("direction") == "left_to_right" else "R->L"
        return f"line {event.get('line_id')}  ID {event.get('track_id')}  {direction}"
    if event_type == "region_entered":
        origin = "initial" if event.get("initial") else "entered"
        return f"region {event.get('region_id')}  ID {event.get('track_id')}  {origin}"
    if event_type == "region_exited":
        return (
            f"region {event.get('region_id')}  ID {event.get('track_id')}  "
            f"exited after {event.get('dwell_frames')} frames"
        )
    return str(event_type)


def _draw_rules(cv2: Any, frame: Any, setup: dict) -> None:
    import numpy as np

    for line in setup["lines"]:
        cv2.line(
            frame,
            _integer_point(line["start"]),
            _integer_point(line["end"]),
            (0, 215, 255),
            2,
            cv2.LINE_AA,
        )
        cv2.putText(
            frame,
            f"line {line['id']}",
            _integer_point(line["start"]),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (0, 215, 255),
            2,
            cv2.LINE_AA,
        )
    for region in setup["regions"]:
        points = [_integer_point(point) for point in region["vertices"]]
        cv2.polylines(frame, [np.array(points)], True, (255, 170, 0), 2)
        cv2.putText(
            frame,
            f"region {region['id']}",
            points[0],
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (255, 170, 0),
            2,
            cv2.LINE_AA,
        )


def _draw_tracks(cv2: Any, frame: Any, tracked: dict) -> None:
    for track in tracked.get("tracks", []):
        x1, y1, x2, y2 = [int(round(value)) for value in track["xyxy"]]
        color = _color(int(track["track_id"]))
        cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
        label = (
            f"ID {track['track_id']}  C{track['class_id']}  "
            f"{float(track['score']):.2f}"
        )
        (text_width, text_height), baseline = cv2.getTextSize(
            label, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 2
        )
        top = max(0, y1 - text_height - baseline - 6)
        cv2.rectangle(frame, (x1, top), (x1 + text_width + 8, y1), color, -1)
        cv2.putText(
            frame,
            label,
            (x1 + 4, y1 - baseline - 3),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (20, 20, 20),
            2,
            cv2.LINE_AA,
        )


def _status_lines(analytics: dict, recent_events: Sequence[str]) -> List[str]:
    lines = ["MBMOT spatial analytics"]
    for count in analytics.get("line_counts", []):
        lines.append(
            f"line {count['line_id']}: L->R {count['left_to_right']}  "
            f"R->L {count['right_to_left']}"
        )
    for count in analytics.get("region_counts", []):
        lines.append(
            f"region {count['region_id']}: inside {count['current_occupancy']}  "
            f"in/out {count['entries']}/{count['exits']}  unique {count['unique_tracks']}"
        )
    lines.extend(recent_events[-3:])
    return lines


def _draw_panel(cv2: Any, frame: Any, lines: Sequence[str]) -> None:
    if not lines:
        return
    overlay = frame.copy()
    panel_height = 16 + 25 * len(lines)
    panel_width = min(frame.shape[1], 590)
    cv2.rectangle(overlay, (0, 0), (panel_width, panel_height), (18, 18, 18), -1)
    cv2.addWeighted(overlay, 0.72, frame, 0.28, 0.0, frame)
    for index, text in enumerate(lines):
        cv2.putText(
            frame,
            text,
            (12, 25 + index * 25),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.58,
            (245, 245, 245),
            1,
            cv2.LINE_AA,
        )


def render_video(
    info: VideoInfo,
    output: Path,
    setup: dict,
    tracked: Sequence[dict],
    analytics: Sequence[dict],
    preview: bool,
) -> None:
    cv2 = load_opencv()
    capture = cv2.VideoCapture(str(info.path))
    if not capture.isOpened():
        raise PipelineError("cannot reopen the captured video for rendering")
    writer = open_video_writer(cv2, output, info.fps, (info.width, info.height))
    recent: List[Tuple[int, str]] = []
    ttl = max(1, int(round(info.fps * 1.5)))
    try:
        for index in range(info.frames):
            ok, frame = capture.read()
            if not ok:
                raise PipelineError(f"video ended before frame {index + 1}")
            frame_id = index + 1
            for event in analytics[index].get("events", []):
                recent.append((frame_id + ttl, _event_text(event)))
            recent = [item for item in recent if item[0] >= frame_id]
            _draw_rules(cv2, frame, setup)
            _draw_tracks(cv2, frame, tracked[index])
            _draw_panel(
                cv2,
                frame,
                _status_lines(analytics[index], [text for _, text in recent]),
            )
            writer.write(frame)
            if preview:
                cv2.imshow("MBMOT video demo", frame)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    raise PipelineError("preview stopped before the output was complete")
    finally:
        capture.release()
        writer.release()
        if preview:
            cv2.destroyAllWindows()
