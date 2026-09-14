///|
test "IoU handles overlap, separation, and invalid internal boxes" {
  let a = BoundingBox::new(0.0, 0.0, 10.0, 10.0)
  let same = BoundingBox::new(0.0, 0.0, 10.0, 10.0)
  let apart = BoundingBox::new(11.0, 0.0, 20.0, 10.0)
  assert_eq(a.iou(same), 1.0)
  assert_eq(a.iou(apart), 0.0)
  let degenerate : BoundingBox = { x1: 1.0, y1: 1.0, x2: 1.0, y2: 2.0, }
  let non_finite : BoundingBox = {
    x1: @double.not_a_number,
    y1: 0.0,
    x2: 1.0,
    y2: 1.0,
  }
  assert_eq(a.iou(degenerate), 0.0)
  assert_eq(a.iou(non_finite), 0.0)
}
