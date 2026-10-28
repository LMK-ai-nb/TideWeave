///|
test "built-in measures reproduce the engine window profile" {
  let c = config(Tumbling(size=10, offset=0), lateness=5)
  let events = [
    { id: "a", key: "k", at: 0, value: 2, fields: None, },
    { id: "b", key: "k", at: 1, value: 4, fields: None, },
    { id: "c", key: "k", at: 9, value: 9, fields: None, },
  ]
  let rows = measure_window(
    c,
    events,
    [count_measure(), sum_measure(), min_measure(), max_measure()],
    watermark=10,
  )
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].count, 3)
  assert_eq(rows[0].phase, "closing")
  assert_true(
    rows[0].measures ==
    [
      { name: "count", value: 3L, },
      { name: "sum", value: 15L, },
      { name: "min", value: 2L, },
      { name: "max", value: 9L, },
    ],
  )
}

///|
test "custom measures fold arbitrary formulas over one window" {
  let c = config(Session(gap=10))
  let events = [
    { id: "a", key: "k", at: 0, value: 1, fields: None, },
    { id: "b", key: "k", at: 3, value: 2, fields: None, },
    { id: "c", key: "k", at: 6, value: 3, fields: None, },
  ]
  // Sum of squares: identity 0, step acc + v*v, finish identity.
  let squares = measure(
    name="sum_squares",
    identity=0,
    step=fn(acc, v) { acc + v * v },
    finish=fn(acc, _) { acc },
  )
  let rows = measure_window(c, events, [average_measure(), squares])
  assert_eq(rows.length(), 1)
  assert_true(rows[0].measures[0] == { name: "avg", value: 2L, })
  assert_true(rows[0].measures[1] == { name: "sum_squares", value: 14L, })
}

///|
test "measure_window rejects empty, duplicate and blank measure names" {
  let c = config(Session(gap=1))
  let blank = measure(name="", identity=0, step=fn(acc, _) { acc }, finish=fn(
    acc,
    _,
  ) {
    acc
  })
  assert_true(
    try {
      ignore(measure_window(c, [], []))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(measure_window(c, [], [count_measure(), count_measure()]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(measure_window(c, [], [blank]))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "built-in min and max measures return zero for empty input" {
  let m = min_measure()
  let x = max_measure()
  assert_true((m.finish)(m.identity, 0L) == 0L)
  assert_true((x.finish)(x.identity, 0L) == 0L)
}

///|
test "measure_window shares assignment and session grouping with the engine" {
  let c = config(Sliding(size=10, slide=4, offset=1))
  let events = [
    { id: "a", key: "k", at: 0, value: 1, fields: None, },
    { id: "b", key: "k", at: 3, value: 1, fields: None, },
  ]
  let rows = measure_window(c, events, [count_measure()])
  let native = aggregate(c, events)
  assert_eq(rows.length(), native.length())
  for i in 0..<rows.length() {
    assert_eq(rows[i].start, native[i].start)
    assert_eq(rows[i].end, native[i].end)
    assert_eq(rows[i].count, native[i].count)
  }
}
