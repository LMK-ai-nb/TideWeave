///|
test "fixed assignment uses mathematical floor at negative aligned starts" {
  assert_eq(assign_fixed(Tumbling(size=10, offset=3), 0), [(-7, 3)])
  assert_eq(assign_fixed(Tumbling(size=10, offset=3), 3), [(3, 13)])
  assert_eq(assign_fixed(Sliding(size=10, slide=4, offset=1), 0), [
    (-7, 3),
    (-3, 7),
  ])
  assert_eq(assign_fixed(Sliding(size=10, slide=4, offset=1), 3), [
    (-3, 7),
    (1, 11),
  ])
}

///|
test "fixed aggregates preserve signed values, member order and wide sums" {
  let c = config(Tumbling(size=10, offset=0), lateness=5)
  let rows = aggregate(
    c,
    [
      { id: "z", key: "工厂", at: 9, value: 1000000000, fields: None, },
      { id: "a", key: "工厂", at: 0, value: 1000000000, fields: None, },
      { id: "b", key: "工厂", at: 1, value: 1000000000, fields: None, },
      { id: "n", key: "工厂", at: 10, value: -7, fields: None, },
    ],
    watermark=10,
  )
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].sum, 3000000000L)
  assert_eq(rows[0].members, ["a", "b", "z"])
  assert_eq(rows[0].phase, "closing")
  assert_eq(rows[1].min, -7)
}

///|
test "assignment agrees with independent interval membership enumeration" {
  for size in 1..<=16 {
    for slide in 1..<=size {
      for offset in 0..<slide {
        for at in 0..<=20 {
          let expected = []
          for n in -40..<=40 {
            let start = n * slide + offset
            if start <= at && at < start + size {
              expected.push((start, start + size))
            }
          }
          assert_eq(assign_fixed(Sliding(size~, slide~, offset~), at), expected)
        }
      }
    }
  }
}
