///|
priv struct MotionState {
  mean : FixedArray[Double]
  covariance : FixedArray[Double]
}

///|
fn squared(value : Double) -> Double {
  value * value
}

///|
fn matrix_index(row : Int, column : Int, width : Int) -> Int {
  row * width + column
}

///|
fn positive_scale(value : Double) -> Double {
  let magnitude = value.abs()
  if magnitude < 1.0e-6 {
    1.0e-6
  } else {
    magnitude
  }
}

///|
fn bbox_measurement(bbox : BoundingBox) -> FixedArray[Double] {
  let width = bbox.x2 - bbox.x1
  let height = bbox.y2 - bbox.y1
  let measurement = FixedArray::make(4, 0.0)
  measurement[0] = bbox.x1 + width * 0.5
  measurement[1] = bbox.y1 + height * 0.5
  measurement[2] = width / height
  measurement[3] = height
  measurement
}

///|
fn measurement_bbox(measurement : FixedArray[Double]) -> BoundingBox? {
  let center_x = measurement[0]
  let center_y = measurement[1]
  let aspect = measurement[2]
  let height = measurement[3]
  let width = aspect * height
  if !is_finite(center_x) ||
    !is_finite(center_y) ||
    !is_finite(aspect) ||
    !is_finite(height) ||
    !is_finite(width) ||
    aspect <= 0.0 ||
    height <= 0.0 ||
    width <= 0.0 {
    return None
  }
  Some({
    x1: center_x - width * 0.5,
    y1: center_y - height * 0.5,
    x2: center_x + width * 0.5,
    y2: center_y + height * 0.5,
  })
}

///|
fn MotionState::init(bbox : BoundingBox) -> MotionState {
  let measurement = bbox_measurement(bbox)
  let mean = FixedArray::make(8, 0.0)
  for index in 0..<4 {
    mean[index] = measurement[index]
  }
  let height = positive_scale(measurement[3])
  let position = 2.0 * 0.05 * height
  let velocity = 10.0 * 0.00625 * height
  let deviations : FixedArray[Double] = [
    position, position, 1.0e-2, position, velocity, velocity, 1.0e-5, velocity,
  ]
  let covariance = FixedArray::make(64, 0.0)
  for index in 0..<8 {
    covariance[matrix_index(index, index, 8)] = squared(deviations[index])
  }
  { mean, covariance }
}

///|
fn MotionState::predict(
  self : MotionState,
  stop_height_velocity : Bool,
) -> MotionState {
  let source_mean = self.mean.copy()
  if stop_height_velocity {
    source_mean[7] = 0.0
  }
  let mean = source_mean.copy()
  for index in 0..<4 {
    mean[index] = source_mean[index] + source_mean[index + 4]
  }
  let covariance = FixedArray::make(64, 0.0)
  for row in 0..<8 {
    for column in 0..<8 {
      let mut value = self.covariance[matrix_index(row, column, 8)]
      if row < 4 {
        value += self.covariance[matrix_index(row + 4, column, 8)]
      }
      if column < 4 {
        value += self.covariance[matrix_index(row, column + 4, 8)]
      }
      if row < 4 && column < 4 {
        value += self.covariance[matrix_index(row + 4, column + 4, 8)]
      }
      covariance[matrix_index(row, column, 8)] = value
    }
  }
  let height = positive_scale(source_mean[3])
  let deviations : FixedArray[Double] = [
    0.05 * height,
    0.05 * height,
    1.0e-2,
    0.05 * height,
    0.00625 * height,
    0.00625 * height,
    1.0e-5,
    0.00625 * height,
  ]
  for index in 0..<8 {
    covariance[matrix_index(index, index, 8)] += squared(deviations[index])
  }
  { mean, covariance }
}

///|
fn MotionState::projection(
  self : MotionState,
) -> (FixedArray[Double], FixedArray[Double]) {
  let mean = FixedArray::make(4, 0.0)
  for index in 0..<4 {
    mean[index] = self.mean[index]
  }
  let covariance = FixedArray::make(16, 0.0)
  for row in 0..<4 {
    for column in 0..<4 {
      covariance[matrix_index(row, column, 4)] = self.covariance[matrix_index(
          row, column, 8,
        )]
    }
  }
  let height = positive_scale(self.mean[3])
  let deviations : FixedArray[Double] = [
    0.05 * height,
    0.05 * height,
    1.0e-1,
    0.05 * height,
  ]
  for index in 0..<4 {
    covariance[matrix_index(index, index, 4)] += squared(deviations[index])
  }
  (mean, covariance)
}

///|
fn cholesky4(matrix : FixedArray[Double]) -> FixedArray[Double]? {
  let lower = FixedArray::make(16, 0.0)
  for row in 0..<4 {
    for column in 0..<=row {
      let mut value = matrix[matrix_index(row, column, 4)]
      for inner in 0..<column {
        value -= lower[matrix_index(row, inner, 4)] *
          lower[matrix_index(column, inner, 4)]
      }
      if row == column {
        if !is_finite(value) || value <= 1.0e-12 {
          return None
        }
        lower[matrix_index(row, column, 4)] = value.sqrt()
      } else {
        let divisor = lower[matrix_index(column, column, 4)]
        if !is_finite(divisor) || divisor <= 0.0 {
          return None
        }
        lower[matrix_index(row, column, 4)] = value / divisor
      }
    }
  }
  Some(lower)
}

///|
fn solve_cholesky4(
  lower : FixedArray[Double],
  right_hand_side : FixedArray[Double],
) -> FixedArray[Double]? {
  let forward = FixedArray::make(4, 0.0)
  for row in 0..<4 {
    let mut value = right_hand_side[row]
    for column in 0..<row {
      value -= lower[matrix_index(row, column, 4)] * forward[column]
    }
    let divisor = lower[matrix_index(row, row, 4)]
    if !is_finite(value) || !is_finite(divisor) || divisor <= 0.0 {
      return None
    }
    forward[row] = value / divisor
  }
  let solution = FixedArray::make(4, 0.0)
  for offset in 0..<4 {
    let row = 3 - offset
    let mut value = forward[row]
    for column in (row + 1)..<4 {
      value -= lower[matrix_index(column, row, 4)] * solution[column]
    }
    let divisor = lower[matrix_index(row, row, 4)]
    if !is_finite(value) || !is_finite(divisor) || divisor <= 0.0 {
      return None
    }
    solution[row] = value / divisor
  }
  Some(solution)
}

///|
fn MotionState::correct_checked(
  self : MotionState,
  bbox : BoundingBox,
) -> MotionState? {
  let (projected_mean, projected_covariance) = self.projection()
  guard cholesky4(projected_covariance) is Some(lower) else { return None }
  let gain = FixedArray::make(32, 0.0)
  for state_row in 0..<8 {
    let right_hand_side = FixedArray::make(4, 0.0)
    for measurement_column in 0..<4 {
      right_hand_side[measurement_column] = self.covariance[matrix_index(
          state_row, measurement_column, 8,
        )]
    }
    guard solve_cholesky4(lower, right_hand_side) is Some(solution) else {
      return None
    }
    for measurement_column in 0..<4 {
      gain[matrix_index(state_row, measurement_column, 4)] = solution[measurement_column]
    }
  }
  let measurement = bbox_measurement(bbox)
  let innovation = FixedArray::make(4, 0.0)
  for index in 0..<4 {
    innovation[index] = measurement[index] - projected_mean[index]
  }
  let mean = self.mean.copy()
  for state_row in 0..<8 {
    for measurement_column in 0..<4 {
      mean[state_row] += gain[matrix_index(state_row, measurement_column, 4)] *
        innovation[measurement_column]
    }
    if !is_finite(mean[state_row]) {
      return None
    }
  }
  let covariance = FixedArray::make(64, 0.0)
  for row in 0..<8 {
    for column in 0..<8 {
      let mut correction = 0.0
      for left in 0..<4 {
        for right in 0..<4 {
          correction += gain[matrix_index(row, left, 4)] *
            projected_covariance[matrix_index(left, right, 4)] *
            gain[matrix_index(column, right, 4)]
        }
      }
      covariance[matrix_index(row, column, 8)] = self.covariance[matrix_index(
          row, column, 8,
        )] -
        correction
    }
  }
  for row in 0..<8 {
    for column in 0..<=row {
      let symmetric = (
          covariance[matrix_index(row, column, 8)] +
          covariance[matrix_index(column, row, 8)]
        ) *
        0.5
      if !is_finite(symmetric) {
        return None
      }
      covariance[matrix_index(row, column, 8)] = symmetric
      covariance[matrix_index(column, row, 8)] = symmetric
    }
    let diagonal = matrix_index(row, row, 8)
    if covariance[diagonal] < 1.0e-12 {
      covariance[diagonal] = 1.0e-12
    }
  }
  Some({ mean, covariance })
}

///|
fn MotionState::correct(self : MotionState, bbox : BoundingBox) -> MotionState {
  match self.correct_checked(bbox) {
    Some(corrected) if corrected.finite() &&
      corrected.positive_diagonal() &&
      corrected.bbox() is Some(_) => corrected
    None => MotionState::init(bbox)
    _ => MotionState::init(bbox)
  }
}

///|
fn MotionState::bbox(self : MotionState) -> BoundingBox? {
  let measurement = FixedArray::make(4, 0.0)
  for index in 0..<4 {
    measurement[index] = self.mean[index]
  }
  measurement_bbox(measurement)
}

///|
fn MotionState::finite(self : MotionState) -> Bool {
  for value in self.mean {
    if !is_finite(value) {
      return false
    }
  }
  for value in self.covariance {
    if !is_finite(value) {
      return false
    }
  }
  true
}

///|
fn MotionState::positive_diagonal(self : MotionState) -> Bool {
  for index in 0..<8 {
    if self.covariance[matrix_index(index, index, 8)] <= 0.0 {
      return false
    }
  }
  true
}
