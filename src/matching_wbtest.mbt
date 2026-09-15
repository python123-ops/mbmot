///|
fn pair_tuples(matches : Array[MatchPair]) -> Array[(Int, Int)] {
  matches.map(pair => (pair.track_index, pair.detection_index))
}

///|
priv struct MatchObjective {
  count : Int
  cost : Double
}

///|
fn better_objective(left : MatchObjective, right : MatchObjective) -> Bool {
  left.count > right.count ||
  (left.count == right.count && left.cost < right.cost)
}

///|
fn brute_force_from(
  costs : Array[Array[Double]],
  max_cost : Double,
  row : Int,
  used : Array[Bool],
) -> MatchObjective {
  if row == costs.length() {
    return { count: 0, cost: 0.0, }
  }
  let mut best = brute_force_from(costs, max_cost, row + 1, used)
  for column in 0..<used.length() {
    let edge = costs[row][column]
    if !used[column] && is_finite(edge) && edge >= 0.0 && edge <= max_cost {
      used[column] = true
      let rest = brute_force_from(costs, max_cost, row + 1, used)
      used[column] = false
      let candidate : MatchObjective = {
        count: rest.count + 1,
        cost: rest.cost + edge,
      }
      if better_objective(candidate, best) {
        best = candidate
      }
    }
  }
  best
}

///|
fn brute_force_objective(
  costs : Array[Array[Double]],
  max_cost : Double,
) -> MatchObjective {
  if costs.length() == 0 || costs[0].length() == 0 {
    return { count: 0, cost: 0.0, }
  }
  brute_force_from(costs, max_cost, 0, Array::make(costs[0].length(), false))
}

///|
fn result_objective(
  costs : Array[Array[Double]],
  matches : Array[MatchPair],
) -> MatchObjective {
  let mut total = 0.0
  for pair in matches {
    total += costs[pair.track_index][pair.detection_index]
  }
  { count: matches.length(), cost: total, }
}

///|
test "optimal matching handles empty and rectangular matrices" {
  assert_eq(optimal_matches([], 1.0).length(), 0)
  assert_eq(optimal_matches([[]], 1.0).length(), 0)
  let matches = optimal_matches([[0.2, 0.4, 0.6]], 0.5)
  debug_inspect(pair_tuples(matches), content="[(0, 0)]")
}

///|
test "matching applies the gate before assignment" {
  let matches = optimal_matches([[0.1, 0.9], [0.9, 0.2]], 0.5)
  debug_inspect(pair_tuples(matches), content="[(0, 0), (1, 1)]")
}

///|
test "matching escapes a greedy local choice" {
  let matches = optimal_matches([[0.10, 0.20], [0.11, 0.90]], 1.0)
  debug_inspect(pair_tuples(matches), content="[(0, 1), (1, 0)]")
}

///|
test "matching resolves exact ties by row then input order" {
  let square = optimal_matches([[0.2, 0.2], [0.2, 0.2]], 0.5)
  debug_inspect(pair_tuples(square), content="[(0, 0), (1, 1)]")
  let one_detection = optimal_matches([[0.2], [0.2]], 0.5)
  debug_inspect(pair_tuples(one_detection), content="[(0, 0)]")
}

///|
test "small rectangular assignments agree with exhaustive search" {
  let cases : Array[Array[Array[Double]]] = [
    [[0.1]],
    [[0.3, 0.1, 0.2]],
    [[0.4], [0.2]],
    [[0.10, 0.20], [0.11, 0.90]],
    [[0.1, 0.8], [0.7, 0.2], [0.3, 0.4]],
    [[0.4, 0.2, 0.9], [0.1, 0.3, 0.2]],
  ]
  for costs in cases {
    let expected = brute_force_objective(costs, 0.5)
    let actual = result_objective(costs, optimal_matches(costs, 0.5))
    assert_eq(actual.count, expected.count)
    assert_true(actual.cost.is_close(expected.cost, absolute_tolerance=1.0e-12))
  }
}
