///|
priv struct MatchPair {
  track_index : Int
  detection_index : Int
}

///|
fn hungarian(square : Array[Array[Double]]) -> Array[Int] {
  let size = square.length()
  if size == 0 {
    return []
  }
  let row_potential = Array::make(size + 1, 0.0)
  let column_potential = Array::make(size + 1, 0.0)
  let column_row = Array::make(size + 1, 0)
  let previous_column = Array::make(size + 1, 0)
  for row in 1..<=size {
    column_row[0] = row
    let minimum = Array::make(size + 1, 1.0e300)
    let used = Array::make(size + 1, false)
    let mut column = 0
    for ;; {
      used[column] = true
      let current_row = column_row[column]
      let mut delta = 1.0e300
      let mut next_column = 0
      for candidate_column in 1..<=size {
        if !used[candidate_column] {
          let reduced = square[current_row - 1][candidate_column - 1] -
            row_potential[current_row] -
            column_potential[candidate_column]
          if reduced < minimum[candidate_column] {
            minimum[candidate_column] = reduced
            previous_column[candidate_column] = column
          }
          if minimum[candidate_column] < delta {
            delta = minimum[candidate_column]
            next_column = candidate_column
          }
        }
      }
      for candidate_column in 0..<=size {
        if used[candidate_column] {
          row_potential[column_row[candidate_column]] += delta
          column_potential[candidate_column] -= delta
        } else {
          minimum[candidate_column] -= delta
        }
      }
      column = next_column
      if column_row[column] == 0 {
        break
      }
    }
    for ;; {
      let prior = previous_column[column]
      column_row[column] = column_row[prior]
      column = prior
      if column == 0 {
        break
      }
    }
  }
  let assignment = Array::make(size, -1)
  for column in 1..<=size {
    if column_row[column] > 0 {
      assignment[column_row[column] - 1] = column - 1
    }
  }
  assignment
}

///|
fn optimal_matches(
  costs : Array[Array[Double]],
  max_cost : Double,
) -> Array[MatchPair] {
  let track_count = costs.length()
  if track_count == 0 {
    return []
  }
  let detection_count = costs[0].length()
  if detection_count == 0 {
    return []
  }
  let size = track_count + detection_count
  let unmatched_cost = size.to_double() + 1.0
  let invalid_cost = unmatched_cost * 3.0
  let square = Array::makei(size, row => {
    Array::makei(size, column => {
      if row < track_count && column < detection_count {
        let cost = costs[row][column]
        if is_finite(cost) && cost >= 0.0 && cost <= max_cost {
          cost
        } else {
          invalid_cost
        }
      } else if row < track_count || column < detection_count {
        unmatched_cost
      } else {
        0.0
      }
    })
  })
  let assignment = hungarian(square)
  let matches : Array[MatchPair] = []
  for track_index in 0..<track_count {
    let detection_index = assignment[track_index]
    if detection_index >= 0 && detection_index < detection_count {
      let cost = costs[track_index][detection_index]
      if is_finite(cost) && cost >= 0.0 && cost <= max_cost {
        matches.push({ track_index, detection_index, })
      }
    }
  }
  matches
}
