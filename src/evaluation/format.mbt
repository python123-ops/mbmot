///|
fn line_error(line : Int, message : String) -> MotError {
  InvalidMotLine(line~, message~)
}

///|
fn fields_of(line : StringView) -> Array[StringView] {
  let fields : Array[StringView] = []
  for field in line.split(",") {
    fields.push(field.trim())
  }
  fields
}

///|
fn parse_int_field(
  field : StringView,
  line : Int,
  name : String,
) -> Int raise MotError {
  @string.parse_int(field) catch {
    _ => raise line_error(line, "invalid \{name}")
  }
}

///|
fn parse_double_field(
  field : StringView,
  line : Int,
  name : String,
) -> Double raise MotError {
  let value = @string.parse_double(field) catch {
    _ => raise line_error(line, "invalid \{name}")
  }
  if value.is_nan() || value.is_inf() {
    raise line_error(line, "\{name} must be finite")
  }
  value
}

///|
fn parse_object(
  fields : Array[StringView],
  line : Int,
  confidence : Double,
) -> MotObject raise MotError {
  let frame = parse_int_field(fields[0], line, "frame")
  let identity = parse_int_field(fields[1], line, "identity")
  let left = parse_double_field(fields[2], line, "left")
  let top = parse_double_field(fields[3], line, "top")
  let width = parse_double_field(fields[4], line, "width")
  let height = parse_double_field(fields[5], line, "height")
  if frame <= 0 {
    raise line_error(line, "frame must be positive")
  }
  if identity <= 0 {
    raise line_error(line, "identity must be positive")
  }
  let bbox = @mbmot.BoundingBox::from_xywh(left, top, width, height) catch {
    _ =>
      raise line_error(
        line, "bounding box must have finite coordinates and positive size",
      )
  }
  MotObject::new(frame, identity, bbox, confidence) catch {
    error => raise line_error(line, error.message())
  }
}

///|
fn object_key(object : MotObject) -> String {
  "\{object.frame}:\{object.identity}"
}

///|
/// Parses marked MOTChallenge ground truth rows with nine or ten columns.
/// Rows whose seventh column is zero are validated but excluded.
pub fn parse_ground_truth(text : StringView) -> Array[MotObject] raise MotError {
  let objects : Array[MotObject] = []
  let seen : Map[String, Bool] = Map([])
  let mut line_number = 0
  for raw_line in text.split("\n") {
    line_number += 1
    let line = raw_line.trim()
    if line.length() == 0 {
      continue
    }
    let fields = fields_of(line)
    if fields.length() != 9 && fields.length() != 10 {
      raise line_error(
        line_number, "ground truth row must contain 9 or 10 columns",
      )
    }
    let mark = parse_int_field(fields[6], line_number, "mark")
    if mark != 0 && mark != 1 {
      raise line_error(line_number, "ground truth mark must be 0 or 1")
    }
    let object = parse_object(fields, line_number, 1.0)
    ignore(parse_int_field(fields[7], line_number, "class"))
    ignore(parse_double_field(fields[8], line_number, "visibility"))
    if fields.length() == 10 {
      ignore(parse_double_field(fields[9], line_number, "world z"))
    }
    if mark == 1 {
      let key = object_key(object)
      if seen.contains(key) {
        raise line_error(line_number, "duplicate frame and identity")
      }
      seen[key] = true
      objects.push(object)
    }
  }
  objects.sort_by((left, right) => {
    if left.frame != right.frame {
      left.frame - right.frame
    } else {
      left.identity - right.identity
    }
  })
  objects
}

///|
/// Parses ten-column MOTChallenge tracker result rows.
pub fn parse_tracker_results(
  text : StringView,
) -> Array[MotObject] raise MotError {
  let objects : Array[MotObject] = []
  let seen : Map[String, Bool] = Map([])
  let mut line_number = 0
  for raw_line in text.split("\n") {
    line_number += 1
    let line = raw_line.trim()
    if line.length() == 0 {
      continue
    }
    let fields = fields_of(line)
    if fields.length() != 10 {
      raise line_error(line_number, "tracker row must contain 10 columns")
    }
    let confidence = parse_double_field(fields[6], line_number, "confidence")
    let object = parse_object(fields, line_number, confidence)
    ignore(parse_double_field(fields[7], line_number, "world x"))
    ignore(parse_double_field(fields[8], line_number, "world y"))
    ignore(parse_double_field(fields[9], line_number, "world z"))
    let key = object_key(object)
    if seen.contains(key) {
      raise line_error(line_number, "duplicate frame and identity")
    }
    seen[key] = true
    objects.push(object)
  }
  objects.sort_by((left, right) => {
    if left.frame != right.frame {
      left.frame - right.frame
    } else {
      left.identity - right.identity
    }
  })
  objects
}

///|
/// Encodes tracker observations as ten-column MOTChallenge rows.
pub fn encode_tracker_results(objects : Array[MotObject]) -> String {
  let sorted = objects.copy()
  sorted.sort_by((left, right) => {
    if left.frame != right.frame {
      left.frame - right.frame
    } else {
      left.identity - right.identity
    }
  })
  let output = StringBuilder()
  for index, object in sorted {
    let (left, top, width, height) = object.bbox.to_xywh()
    if index > 0 {
      output.write_string("\n")
    }
    output.write_string(
      "\{object.frame},\{object.identity},\{left},\{top},\{width},\{height},\{object.confidence},-1,-1,-1",
    )
  }
  output.to_string()
}

///|
/// Converts visible MBMOT tracks into MOT observations at their last observed frame.
pub fn objects_from_tracks(tracks : Array[@mbmot.Track]) -> Array[MotObject] {
  let objects : Array[MotObject] = []
  for track in tracks {
    objects.push({
      frame: track.last_frame(),
      identity: track.track_id(),
      bbox: track.bbox(),
      confidence: track.score(),
    })
  }
  objects.sort_by((left, right) => {
    if left.frame != right.frame {
      left.frame - right.frame
    } else {
      left.identity - right.identity
    }
  })
  objects
}
