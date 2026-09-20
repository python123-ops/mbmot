///|
/// One detector observation from a MOTChallenge detection file.
pub struct MotDetection {
  frame : Int
  bbox : @mbmot.BoundingBox
  confidence : Double
  input_order : Int
} derive(Debug, Eq)

///|
pub fn MotDetection::new(
  frame : Int,
  bbox : @mbmot.BoundingBox,
  confidence : Double,
) -> MotDetection raise MotError {
  if frame <= 0 {
    raise InvalidConfig("MOT detection frame must be positive")
  }
  if confidence.is_nan() ||
    confidence.is_inf() ||
    confidence < 0.0 ||
    confidence > 1.0 {
    raise InvalidConfig("MOT detection confidence must be in [0, 1]")
  }
  { frame, bbox, confidence, input_order: 0, }
}

///|
pub fn MotDetection::frame(self : MotDetection) -> Int {
  self.frame
}

///|
pub fn MotDetection::bbox(self : MotDetection) -> @mbmot.BoundingBox {
  self.bbox
}

///|
pub fn MotDetection::confidence(self : MotDetection) -> Double {
  self.confidence
}

///|
/// Parses seven- or ten-column MOTChallenge detector rows in their original
/// order. World coordinates in ten-column rows are validated and ignored.
pub fn parse_detections(
  text : StringView,
) -> Array[MotDetection] raise MotError {
  let detections : Array[MotDetection] = []
  let mut line_number = 0
  for raw_line in text.split("\n") {
    line_number += 1
    let line = raw_line.trim()
    if line.length() == 0 {
      continue
    }
    let fields = fields_of(line)
    if fields.length() != 7 && fields.length() != 10 {
      raise line_error(
        line_number, "detection row must contain 7 or 10 columns",
      )
    }
    let frame = parse_int_field(fields[0], line_number, "frame")
    ignore(parse_int_field(fields[1], line_number, "identity"))
    let left = parse_double_field(fields[2], line_number, "left")
    let top = parse_double_field(fields[3], line_number, "top")
    let width = parse_double_field(fields[4], line_number, "width")
    let height = parse_double_field(fields[5], line_number, "height")
    let confidence = parse_double_field(fields[6], line_number, "confidence")
    if fields.length() == 10 {
      ignore(parse_double_field(fields[7], line_number, "world x"))
      ignore(parse_double_field(fields[8], line_number, "world y"))
      ignore(parse_double_field(fields[9], line_number, "world z"))
    }
    let bbox = @mbmot.BoundingBox::from_xywh(left, top, width, height) catch {
      _ =>
        raise line_error(
          line_number, "bounding box must have finite coordinates and positive size",
        )
    }
    ignore(
      MotDetection::new(frame, bbox, confidence) catch {
        error => raise line_error(line_number, error.message())
      },
    )
    detections.push({ frame, bbox, confidence, input_order: line_number, })
  }
  detections.sort_by((left, right) => {
    if left.frame != right.frame {
      left.frame - right.frame
    } else {
      left.input_order - right.input_order
    }
  })
  detections
}

///|
/// Runs MBMOT over a frame-ordered detector stream and returns visible tracks.
pub fn track_detections(
  source : Array[MotDetection],
  config : @mbmot.TrackerConfig,
) -> Array[MotObject] raise MotError {
  let tracker = @mbmot.Tracker::new(config)
  let output : Array[MotObject] = []
  let mut offset = 0
  let mut previous_frame = 0
  while offset < source.length() {
    let frame = source[offset].frame
    if frame < previous_frame {
      raise InvalidConfig("MOT detections must be ordered by frame")
    }
    let frame_detections : Array[@mbmot.Detection] = []
    while offset < source.length() && source[offset].frame == frame {
      let item = source[offset]
      let detection = @mbmot.Detection::new(item.bbox, item.confidence, 0) catch {
        error => raise InvalidConfig(error.message())
      }
      frame_detections.push(detection)
      offset += 1
    }
    let result = tracker.update(frame, frame_detections) catch {
      error => raise InvalidConfig(error.message())
    }
    for object in objects_from_tracks(result.tracks()) {
      output.push(object)
    }
    previous_frame = frame
  }
  output
}
