///|
fn object(
  frame : Int,
  identity : Int,
  x : Double,
) -> @evaluation.MotObject raise {
  @evaluation.MotObject::new(
    frame,
    identity,
    @mbmot.BoundingBox::from_xywh(x, 0.0, 10.0, 10.0),
    1.0,
  )
}

///|
test "perfect sequence has unit CLEAR and identity scores" {
  let truth = [object(1, 1, 0.0), object(2, 1, 1.0)]
  let result = [object(1, 7, 0.0), object(2, 7, 1.0)]
  let report = @evaluation.evaluate(
    truth,
    result,
    @evaluation.EvaluationConfig::default(),
  )
  assert_eq(report.frames(), 2)
  assert_eq(report.ground_truth_detections(), 2)
  assert_eq(report.tracker_detections(), 2)
  assert_eq(report.true_positives(), 2)
  assert_eq(report.false_positives(), 0)
  assert_eq(report.false_negatives(), 0)
  assert_eq(report.identity_switches(), 0)
  assert_eq(report.mota(), 1.0)
  assert_eq(report.motp(), 1.0)
  assert_eq(report.id_true_positives(), 2)
  assert_eq(report.id_false_positives(), 0)
  assert_eq(report.id_false_negatives(), 0)
  assert_eq(report.id_precision(), 1.0)
  assert_eq(report.id_recall(), 1.0)
  assert_eq(report.idf1(), 1.0)
}

///|
test "missed and spurious boxes remain visible in raw and identity counts" {
  let truth = [object(1, 1, 0.0), object(2, 1, 0.0)]
  let result = [object(1, 7, 0.0), object(2, 8, 100.0)]
  let report = @evaluation.evaluate(
    truth,
    result,
    @evaluation.EvaluationConfig::default(),
  )
  assert_eq(report.true_positives(), 1)
  assert_eq(report.false_positives(), 1)
  assert_eq(report.false_negatives(), 1)
  assert_eq(report.mota(), 0.0)
  assert_eq(report.motp(), 1.0)
  assert_eq(report.id_true_positives(), 1)
  assert_eq(report.id_false_positives(), 1)
  assert_eq(report.id_false_negatives(), 1)
  assert_true(report.idf1().is_close(0.5))
}

///|
test "an identity change is distinct from detection accuracy" {
  let truth = [object(1, 1, 0.0), object(2, 1, 1.0), object(3, 1, 2.0)]
  let result = [object(1, 10, 0.0), object(2, 10, 1.0), object(3, 20, 2.0)]
  let report = @evaluation.evaluate(
    truth,
    result,
    @evaluation.EvaluationConfig::default(),
  )
  assert_eq(report.true_positives(), 3)
  assert_eq(report.identity_switches(), 1)
  assert_true(report.mota().is_close(2.0 / 3.0))
  assert_eq(report.id_true_positives(), 2)
  assert_eq(report.id_false_positives(), 1)
  assert_eq(report.id_false_negatives(), 1)
  assert_true(report.idf1().is_close(2.0 / 3.0))
}

///|
test "empty sequences produce finite zero metrics" {
  let report = @evaluation.evaluate(
    [],
    [],
    @evaluation.EvaluationConfig::default(),
  )
  assert_eq(report.frames(), 0)
  assert_eq(report.mota(), 0.0)
  assert_eq(report.motp(), 0.0)
  assert_eq(report.idf1(), 0.0)
}

///|
test "prediction-only sequence keeps its false positives in MOTA" {
  let report = @evaluation.evaluate(
    [],
    [object(2, 9, 0.0)],
    @evaluation.EvaluationConfig::default(),
  )
  assert_eq(report.frames(), 2)
  assert_eq(report.false_positives(), 1)
  assert_eq(report.mota(), -1.0)
  assert_eq(report.id_false_positives(), 1)
}

///|
test "report JSON preserves the counts used for derived metrics" {
  let report = @evaluation.evaluate(
    [object(1, 1, 0.0)],
    [object(1, 7, 0.0)],
    @evaluation.EvaluationConfig::default(),
  )
  assert_eq(
    @evaluation.encode_report_json(report),
    (
      #|{"match_iou_threshold":0.5,"frames":1,"ground_truth_detections":1,"tracker_detections":1,"true_positives":1,"false_positives":0,"false_negatives":0,"identity_switches":0,"mota":1,"motp":1,"id_true_positives":1,"id_false_positives":0,"id_false_negatives":0,"id_precision":1,"id_recall":1,"idf1":1}
    ),
  )
}

///|
test "IoU threshold validation rejects zero" {
  try @evaluation.EvaluationConfig::new(match_iou_threshold=0.0) catch {
    error => assert_eq(error.message(), "match IoU threshold must be in (0, 1]")
  } noraise {
    _ => fail("zero IoU threshold must be rejected")
  }
}
