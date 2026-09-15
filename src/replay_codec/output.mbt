///|
fn write_double(builder : StringBuilder, value : Double) -> Unit {
  builder.write_string(Json::number(value).stringify())
}

///|
fn write_int_array(builder : StringBuilder, values : Array[Int]) -> Unit {
  builder.write_char('[')
  for index, value in values {
    if index > 0 {
      builder.write_char(',')
    }
    builder.write_string(value.to_string())
  }
  builder.write_char(']')
}

///|
fn write_track(builder : StringBuilder, track : @mbmot.Track) -> Unit {
  let box = track.bbox()
  builder.write_string(
    (
      #|{"track_id":
    ),
  )
  builder.write_string(track.track_id().to_string())
  builder.write_string(
    (
      #|,"xyxy":[
    ),
  )
  write_double(builder, box.x1())
  builder.write_char(',')
  write_double(builder, box.y1())
  builder.write_char(',')
  write_double(builder, box.x2())
  builder.write_char(',')
  write_double(builder, box.y2())
  builder.write_string(
    (
      #|],"score":
    ),
  )
  write_double(builder, track.score())
  builder.write_string(
    (
      #|,"class_id":
    ),
  )
  builder.write_string(track.class_id().to_string())
  builder.write_string(
    (
      #|,"first_frame":
    ),
  )
  builder.write_string(track.first_frame().to_string())
  builder.write_string(
    (
      #|,"last_frame":
    ),
  )
  builder.write_string(track.last_frame().to_string())
  builder.write_string(
    (
      #|,"hits":
    ),
  )
  builder.write_string(track.hits().to_string())
  builder.write_char('}')
}

///|
pub fn encode_frame_result(frame : Int, result : @mbmot.FrameTracks) -> String {
  let builder = StringBuilder::StringBuilder()
  builder.write_string(
    (
      #|{"frame":
    ),
  )
  builder.write_string(frame.to_string())
  builder.write_string(
    (
      #|,"tracks":[
    ),
  )
  for index, track in result.tracks() {
    if index > 0 {
      builder.write_char(',')
    }
    write_track(builder, track)
  }
  builder.write_string(
    (
      #|],"lost":
    ),
  )
  write_int_array(builder, result.lost())
  builder.write_string(
    (
      #|,"removed":
    ),
  )
  write_int_array(builder, result.removed())
  builder.write_char('}')
  builder.to_string()
}
