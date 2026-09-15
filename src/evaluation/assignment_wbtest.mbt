///|
test "assignment maximizes valid matches before total IoU" {
  let matches = maximum_iou_assignment([[0.9, 0.8], [0.8, 0.0]], 0.5)
  assert_eq(matches, [(0, 1), (1, 0)])
}

///|
test "assignment resolves equal IoU by row and column order" {
  let matches = maximum_iou_assignment([[0.8, 0.8], [0.8, 0.8]], 0.5)
  assert_eq(matches, [(0, 0), (1, 1)])
}

///|
test "assignment handles empty and below-threshold matrices" {
  assert_eq(maximum_iou_assignment([], 0.5), [])
  assert_eq(maximum_iou_assignment([[]], 0.5), [])
  assert_eq(maximum_iou_assignment([[0.49]], 0.5), [])
}
