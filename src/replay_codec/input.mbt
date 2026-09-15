///|
priv struct InputDetection {
  xyxy : Array[Double]
  score : Double
  class_id : Int
} derive(FromJson)

///|
priv struct InputFrame {
  frame : Int
  detections : Array[InputDetection]
} derive(FromJson)

///|
pub(all) suberror ReplayError {
  InvalidJson(String)
  InvalidFrame(String)
  InvalidDetection(index~ : Int, reason~ : String)
} derive(Debug, Eq)

///|
pub fn ReplayError::message(self : ReplayError) -> String {
  match self {
    InvalidJson(reason) => "invalid JSON: " + reason
    InvalidFrame(reason) => "invalid frame: " + reason
    InvalidDetection(index~, reason~) =>
      "invalid detection " + index.to_string() + ": " + reason
  }
}

///|
pub struct ReplayFrame {
  frame : Int
  detections : Array[@mbmot.Detection]
}

///|
pub fn ReplayFrame::frame(self : ReplayFrame) -> Int {
  self.frame
}

///|
pub fn ReplayFrame::detections(self : ReplayFrame) -> Array[@mbmot.Detection] {
  self.detections.copy()
}

///|
fn detection_error(error : @mbmot.TrackerError) -> String {
  match error {
    @mbmot.InvalidBoundingBox(reason) => reason
    @mbmot.InvalidScore(score) => "score outside [0, 1]: " + score.to_string()
    @mbmot.InvalidClassId(class_id) =>
      "class_id must be non-negative: " + class_id.to_string()
    _ => "detection failed validation"
  }
}

///|
pub fn parse_frame_line(line : StringView) -> ReplayFrame raise ReplayError {
  let json = @json.parse(line) catch {
    error => raise InvalidJson(error.to_string())
  }
  let input : InputFrame = @json.from_json(json) catch {
    error => raise InvalidFrame(error.to_string())
  }
  let detections : Array[@mbmot.Detection] = []
  for index, item in input.detections {
    if item.xyxy.length() != 4 {
      raise InvalidDetection(
        index~,
        reason="xyxy must contain exactly four numbers",
      )
    }
    let bbox = @mbmot.BoundingBox::new(
      item.xyxy[0],
      item.xyxy[1],
      item.xyxy[2],
      item.xyxy[3],
    ) catch {
      error => raise InvalidDetection(index~, reason=detection_error(error))
    }
    let detection = @mbmot.Detection::new(bbox, item.score, item.class_id) catch {
      error => raise InvalidDetection(index~, reason=detection_error(error))
    }
    detections.push(detection)
  }
  { frame: input.frame, detections }
}
