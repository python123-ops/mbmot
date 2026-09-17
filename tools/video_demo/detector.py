"""Optional built-in detector used by the recorded-video demonstration."""

from __future__ import annotations

import math
from typing import Any, List

from pipeline import PipelineError


def load_opencv():
    try:
        import cv2
    except ImportError as error:
        raise PipelineError(
            "OpenCV is required; install tools/video_demo/requirements.txt"
        ) from error
    return cv2


class HogPersonDetector:
    """OpenCV's built-in full-body detector exposed as MBMOT detections."""

    def __init__(self, confidence: float, nms_threshold: float) -> None:
        cv2 = load_opencv()
        self._cv2 = cv2
        self._confidence = confidence
        self._nms_threshold = nms_threshold
        self._hog = cv2.HOGDescriptor()
        self._hog.setSVMDetector(cv2.HOGDescriptor_getDefaultPeopleDetector())

    @staticmethod
    def _probability(margin: float) -> float:
        if margin >= 0:
            return 1.0 / (1.0 + math.exp(-margin))
        exp_margin = math.exp(margin)
        return exp_margin / (1.0 + exp_margin)

    def detect(self, frame: Any) -> List[dict]:
        rectangles, margins = self._hog.detectMultiScale(
            frame,
            winStride=(8, 8),
            padding=(8, 8),
            scale=1.05,
        )
        boxes: List[list] = []
        scores: List[float] = []
        for rectangle, raw_margin in zip(rectangles, margins):
            x, y, width, height = [int(value) for value in rectangle]
            score = self._probability(float(raw_margin))
            if score >= self._confidence:
                boxes.append([x, y, width, height])
                scores.append(score)
        if not boxes:
            return []
        selected = self._cv2.dnn.NMSBoxes(
            boxes, scores, self._confidence, self._nms_threshold
        )
        detections: List[dict] = []
        for raw_index in selected:
            index = int(raw_index[0]) if hasattr(raw_index, "__len__") else int(raw_index)
            x, y, width, height = boxes[index]
            detections.append(
                {
                    "xyxy": [float(x), float(y), float(x + width), float(y + height)],
                    "score": scores[index],
                    "class_id": 0,
                }
            )
        detections.sort(key=lambda item: (item["xyxy"][0], item["xyxy"][1]))
        return detections
