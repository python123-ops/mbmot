///|
test "detector boxes reach tracking, region occupancy, and MOT evaluation" {
  let input = "{\"frame\":1,\"width\":20,\"height\":10,\"coordinates\":\"normalized\",\"detections\":[{\"cxcywh\":[0.2,0.4,0.2,0.4],\"score\":0.95,\"class_id\":0}]}"
  let detection_frame = @detection_adapter.parse_yolo_frame(input)
  assert_eq(detection_frame.detections().length(), 1)
  assert_eq(detection_frame.detections()[0].bbox().x1(), 2.0)

  let tracker = @mbmot.Tracker::new(@mbmot.TrackerConfig::default())
  let tracked = tracker.update(
    detection_frame.frame(),
    detection_frame.detections(),
  )
  assert_eq(tracked.tracks()[0].track_id(), 1)

  let region = @analytics.PolygonRegion::new(7, [
    @analytics.Point::new(0.0, 0.0),
    @analytics.Point::new(10.0, 0.0),
    @analytics.Point::new(10.0, 10.0),
    @analytics.Point::new(0.0, 10.0),
  ])
  let analyzer = @analytics.SpatialAnalyzer::new(
    @analytics.AnalyticsConfig::new(
      anchor=@analytics.BottomCenter,
      stable_frames=1,
    ),
    [],
    [region],
  )
  let spatial = analyzer.update_mbmot(detection_frame.frame(), tracked)
  assert_eq(spatial.region_counts()[0].current_occupancy(), 1)
  assert_eq(spatial.region_counts()[0].unique_tracks(), 1)

  let truth = @evaluation.parse_ground_truth("1,1,2,2,4,4,1,1,1\n")
  let observations = @evaluation.objects_from_tracks(tracked.tracks())
  let report = @evaluation.evaluate(
    truth,
    observations,
    @evaluation.EvaluationConfig::default(),
  )
  assert_eq(report.true_positives(), 1)
  assert_eq(report.false_positives(), 0)
  assert_eq(report.idf1(), 1.0)
}
