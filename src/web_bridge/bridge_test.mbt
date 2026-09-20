///|
let setup = "{\"config\":{\"anchor\":\"bottom_center\",\"stable_frames\":1},\"lines\":[{\"id\":4,\"start\":[5,0],\"end\":[5,10]}],\"regions\":[{\"id\":7,\"vertices\":[[0,0],[10,0],[10,10],[0,10]]}]}"

///|
struct CreatedResult {
  session_id : Int
} derive(FromJson)

///|
struct CreatedEnvelope {
  ok : Bool
  result : CreatedResult
} derive(FromJson)

///|
fn create_test_session() -> Int raise {
  let json = try! @json.parse(mbmot_create(setup))
  let envelope : CreatedEnvelope = try! @json.from_json(json)
  assert_true(envelope.ok)
  envelope.result.session_id
}

///|
test "create update and close one browser session" {
  let session_id = create_test_session()
  let output = mbmot_update(
    session_id, "{\"frame\":1,\"detections\":[{\"xyxy\":[1,1,3,5],\"score\":0.9,\"class_id\":0}]}",
  )
  assert_true(output.contains("\"track_id\":1"))
  assert_true(output.contains("\"current_occupancy\":1"))
  assert_true(mbmot_close(session_id).contains("\"closed\":true"))
  assert_true(mbmot_update(session_id, "{}").contains("unknown_session"))
}

///|
test "sessions are isolated and a rejected frame is atomic" {
  let first = create_test_session()
  let second = create_test_session()
  let accepted = "{\"frame\":1,\"detections\":[{\"xyxy\":[1,1,3,5],\"score\":0.9,\"class_id\":0}]}"
  assert_true(mbmot_update(first, accepted).contains("\"track_id\":1"))
  assert_true(mbmot_update(second, accepted).contains("\"track_id\":1"))
  let rejected = mbmot_update(first, accepted)
  assert_true(rejected.contains("invalid_frame"))
  let resumed = mbmot_update(
    first, "{\"frame\":2,\"detections\":[{\"xyxy\":[2,1,4,5],\"score\":0.9,\"class_id\":0}]}",
  )
  assert_true(resumed.contains("\"track_id\":1"))
  assert_true(mbmot_reset(second).contains("\"reset\":true"))
  assert_true(mbmot_update(second, accepted).contains("\"track_id\":1"))
  ignore(mbmot_close(first))
  ignore(mbmot_close(second))
}

///|
test "invalid setup and closed sessions are rejected" {
  assert_true(mbmot_create("{}").contains("invalid_config"))
  assert_true(mbmot_close(999).contains("unknown_session"))
}
