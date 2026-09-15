///|
/// An axis-aligned rectangle in continuous `xyxy` coordinates.
pub struct BoundingBox {
  x1 : Double
  y1 : Double
  x2 : Double
  y2 : Double
} derive(Debug, Eq)

///|
fn is_finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn BoundingBox::valid(self : BoundingBox) -> Bool {
  is_finite(self.x1) &&
  is_finite(self.y1) &&
  is_finite(self.x2) &&
  is_finite(self.y2) &&
  self.x2 > self.x1 &&
  self.y2 > self.y1
}

///|
/// Creates a valid continuous-coordinate bounding box.
pub fn BoundingBox::new(
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
) -> BoundingBox raise TrackerError {
  let bbox = { x1, y1, x2, y2 }
  if !bbox.valid() {
    raise InvalidBoundingBox(
      "coordinates must be finite and satisfy x2 > x1 and y2 > y1",
    )
  }
  bbox
}

///|
/// Creates a box from its top-left corner, width, and height.
pub fn BoundingBox::from_xywh(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> BoundingBox raise TrackerError {
  BoundingBox::new(x, y, x + width, y + height)
}

///|
/// Creates a box from its center, width, and height.
///
/// This is the coordinate order commonly emitted by YOLO-family detectors.
pub fn BoundingBox::from_cxcywh(
  center_x : Double,
  center_y : Double,
  width : Double,
  height : Double,
) -> BoundingBox raise TrackerError {
  let half_width = width / 2.0
  let half_height = height / 2.0
  BoundingBox::new(
    center_x - half_width,
    center_y - half_height,
    center_x + half_width,
    center_y + half_height,
  )
}

///|
/// Returns the left coordinate.
pub fn BoundingBox::x1(self : BoundingBox) -> Double {
  self.x1
}

///|
/// Returns the top coordinate.
pub fn BoundingBox::y1(self : BoundingBox) -> Double {
  self.y1
}

///|
/// Returns the right coordinate.
pub fn BoundingBox::x2(self : BoundingBox) -> Double {
  self.x2
}

///|
/// Returns the bottom coordinate.
pub fn BoundingBox::y2(self : BoundingBox) -> Double {
  self.y2
}

///|
/// Returns the box as its top-left corner, width, and height.
pub fn BoundingBox::to_xywh(
  self : BoundingBox,
) -> (Double, Double, Double, Double) {
  (self.x1, self.y1, self.x2 - self.x1, self.y2 - self.y1)
}

///|
/// Returns the box as its center, width, and height.
pub fn BoundingBox::to_cxcywh(
  self : BoundingBox,
) -> (Double, Double, Double, Double) {
  let width = self.x2 - self.x1
  let height = self.y2 - self.y1
  (self.x1 + width / 2.0, self.y1 + height / 2.0, width, height)
}

///|
fn BoundingBox::area(self : BoundingBox) -> Double {
  if self.valid() {
    (self.x2 - self.x1) * (self.y2 - self.y1)
  } else {
    0.0
  }
}

///|
fn BoundingBox::iou(self : BoundingBox, other : BoundingBox) -> Double {
  if !self.valid() || !other.valid() {
    return 0.0
  }
  let left = if self.x1 > other.x1 { self.x1 } else { other.x1 }
  let top = if self.y1 > other.y1 { self.y1 } else { other.y1 }
  let right = if self.x2 < other.x2 { self.x2 } else { other.x2 }
  let bottom = if self.y2 < other.y2 { self.y2 } else { other.y2 }
  let width = right - left
  let height = bottom - top
  if width <= 0.0 || height <= 0.0 {
    return 0.0
  }
  let intersection = width * height
  intersection / (self.area() + other.area() - intersection)
}
