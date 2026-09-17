///|
priv struct AnalyticsReplayFrame {
  frame : Int
  tracks : Array[@analytics.TrackSample]
  lost : Array[Int]
  removed : Array[Int]
}

///|
fn parse_frame(
  line : StringView,
) -> AnalyticsReplayFrame raise AnalyticsReplayError {
  let json = parse_json(line)
  let input : InputFrame = @json.from_json(json) catch {
    error => raise InvalidFrame(error.to_string())
  }
  let tracks : Array[@analytics.TrackSample] = []
  for index, item in input.tracks {
    if item.xyxy.length() != 4 {
      raise InvalidTrack(
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
      error => raise InvalidTrack(index~, reason=error.message())
    }
    let sample = @analytics.TrackSample::new(item.track_id, bbox, item.class_id) catch {
      error => raise InvalidTrack(index~, reason=error.message())
    }
    tracks.push(sample)
  }
  { frame: input.frame, tracks, lost: input.lost, removed: input.removed, }
}
