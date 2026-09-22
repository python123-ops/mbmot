///|
priv struct InputDetection {
  cxcywh : Array[Double]
  score : Double
  class_id : Int
} derive(FromJson)

///|
priv struct InputFrame {
  frame : Int
  width : Int
  height : Int
  coordinates : String
  detections : Array[InputDetection]
} derive(FromJson)

///|
pub(all) suberror AdapterError {
  InvalidJson(String)
  InvalidFrame(String)
  InvalidDetection(index~ : Int, reason~ : String)
  InvalidClassFilter(String)
  NonIncreasingFrame(previous~ : Int, received~ : Int)
} derive(Debug, Eq)

///|
pub fn AdapterError::message(self : AdapterError) -> String {
  match self {
    InvalidJson(reason) => "invalid JSON: " + reason
    InvalidFrame(reason) => "invalid frame: " + reason
    InvalidDetection(index~, reason~) =>
      "invalid detection " + index.to_string() + ": " + reason
    InvalidClassFilter(reason) => "invalid class filter: " + reason
    NonIncreasingFrame(previous~, received~) =>
      "frame must increase: previous \{previous}, received \{received}"
  }
}

///|
pub struct YoloFrame {
  frame : Int
  detections : Array[@mbmot.Detection]
}

///|
pub fn YoloFrame::frame(self : YoloFrame) -> Int {
  self.frame
}

///|
pub fn YoloFrame::detections(self : YoloFrame) -> Array[@mbmot.Detection] {
  self.detections.copy()
}

///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn validate_filter(classes : Array[Int]?) -> Unit raise AdapterError {
  match classes {
    None => ()
    Some(ids) => {
      if ids.length() == 0 {
        raise InvalidClassFilter("class_ids must not be empty")
      }
      for index, id in ids {
        if id < 0 {
          raise InvalidClassFilter("class_id must be non-negative")
        }
        for previous in 0..<index {
          if ids[previous] == id {
            raise InvalidClassFilter("duplicate class_id: \{id}")
          }
        }
      }
    }
  }
}

///|
fn accepts_class(classes : Array[Int]?, class_id : Int) -> Bool {
  match classes {
    None => true
    Some(ids) => ids.any(id => id == class_id)
  }
}

///|
/// Converts one detector frame to the tracker's pixel-coordinate input.
/// Normalized boxes must fit entirely within [0, 1]. Pixel boxes may extend
/// outside the image, but must have finite coordinates and positive area.
pub fn parse_yolo_frame(
  line : StringView,
  class_ids? : Array[Int] = [],
) -> YoloFrame raise AdapterError {
  let classes = if class_ids.length() == 0 { None } else { Some(class_ids) }
  validate_filter(classes)
  let json = @json.parse(line) catch {
    error => raise InvalidJson(error.to_string())
  }
  let input : InputFrame = @json.from_json(json) catch {
    error => raise InvalidFrame(error.to_string())
  }
  if input.frame < 1 || input.width < 1 || input.height < 1 {
    raise InvalidFrame("frame, width and height must be positive")
  }
  if input.coordinates != "normalized" && input.coordinates != "pixels" {
    raise InvalidFrame("coordinates must be normalized or pixels")
  }
  let detections : Array[@mbmot.Detection] = []
  for index, item in input.detections {
    if item.cxcywh.length() != 4 {
      raise InvalidDetection(index~, reason="cxcywh must contain four numbers")
    }
    if item.class_id < 0 {
      raise InvalidDetection(index~, reason="class_id must be non-negative")
    }
    if !finite(item.score) || item.score < 0.0 || item.score > 1.0 {
      raise InvalidDetection(index~, reason="score must be in [0, 1]")
    }
    for value in item.cxcywh {
      if !finite(value) {
        raise InvalidDetection(index~, reason="cxcywh must be finite")
      }
    }
    let cx = item.cxcywh[0]
    let cy = item.cxcywh[1]
    let width = item.cxcywh[2]
    let height = item.cxcywh[3]
    if width <= 0.0 || height <= 0.0 {
      raise InvalidDetection(index~, reason="width and height must be positive")
    }
    if input.coordinates == "normalized" &&
      (
        cx - width / 2.0 < 0.0 ||
        cx + width / 2.0 > 1.0 ||
        cy - height / 2.0 < 0.0 ||
        cy + height / 2.0 > 1.0
      ) {
      raise InvalidDetection(
        index~,
        reason="normalized box must fit within [0, 1]",
      )
    }
    let scale_x = if input.coordinates == "normalized" {
      input.width.to_double()
    } else {
      1.0
    }
    let scale_y = if input.coordinates == "normalized" {
      input.height.to_double()
    } else {
      1.0
    }
    let bbox = @mbmot.BoundingBox::from_cxcywh(
      cx * scale_x,
      cy * scale_y,
      width * scale_x,
      height * scale_y,
    ) catch {
      _ => raise InvalidDetection(index~, reason="invalid pixel bounding box")
    }
    let detection = @mbmot.Detection::new(bbox, item.score, item.class_id) catch {
      _ => raise InvalidDetection(index~, reason="invalid detection")
    }
    if accepts_class(classes, item.class_id) {
      detections.push(detection)
    }
  }
  { frame: input.frame, detections, }
}

///|
pub fn encode_replay_frame(frame : YoloFrame) -> String {
  let builder = StringBuilder::StringBuilder()
  builder.write_string("{\"frame\":\{frame.frame},\"detections\":[")
  for index, detection in frame.detections {
    if index > 0 {
      builder.write_char(',')
    }
    let box = detection.bbox()
    builder.write_string(
      "{\"xyxy\":[\{Json::number(box.x1()).stringify()},\{Json::number(box.y1()).stringify()},\{Json::number(box.x2()).stringify()},\{Json::number(box.y2()).stringify()}],\"score\":\{Json::number(detection.score()).stringify()},\"class_id\":\{detection.class_id()}}",
    )
  }
  builder.write_string("]}")
  builder.to_string()
}

///|
pub struct YoloSession {
  classes : Array[Int]?
  mut last_frame : Int
  mut lines_read : Int
}

///|
pub fn YoloSession::new(
  class_ids? : Array[Int] = [],
) -> YoloSession raise AdapterError {
  let classes = if class_ids.length() == 0 {
    None
  } else {
    Some(class_ids.copy())
  }
  validate_filter(classes)
  { classes, last_frame: 0, lines_read: 0, }
}

///|
pub fn YoloSession::process_line(
  self : YoloSession,
  line : StringView,
) -> String raise AdapterError {
  self.lines_read += 1
  let frame = parse_yolo_frame(
    line,
    class_ids=match self.classes {
      None => []
      Some(ids) => ids
    },
  )
  if frame.frame() <= self.last_frame {
    raise NonIncreasingFrame(previous=self.last_frame, received=frame.frame())
  }
  let output = encode_replay_frame(frame)
  self.last_frame = frame.frame()
  output
}

///|
pub fn YoloSession::lines_read(self : YoloSession) -> Int {
  self.lines_read
}
