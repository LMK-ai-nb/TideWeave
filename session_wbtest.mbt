///|
test "late bridge merges sessions and its retraction splits them" {
  let c = config(Session(gap=10))
  let a : Event = { id: "a", key: "visitor", at: 0, value: 2, }
  let z : Event = { id: "c", key: "visitor", at: 16, value: 5, }
  let b : Event = { id: "b", key: "visitor", at: 8, value: 3, }
  let split = aggregate(c, [z, a])
  let merged = aggregate(c, [z, b, a])
  assert_eq(split.length(), 2)
  assert_eq(merged.length(), 1)
  assert_eq(merged[0].start, 0)
  assert_eq(merged[0].end, 26)
  assert_eq(merged[0].sum, 10L)
  assert_eq(merged[0].members, ["a", "b", "c"])
  assert_true(aggregate(c, [a, z]) == split)
}

///|
test "touching half-open session intervals remain separate" {
  let rows = aggregate(config(Session(gap=10)), [
    { id: "a", key: "k", at: 0, value: 1, },
    { id: "b", key: "k", at: 10, value: 1, },
    { id: "c", key: "k", at: 19, value: 1, },
  ])
  assert_eq(rows.length(), 2)
  assert_eq(rows[1].members, ["b", "c"])
}

///|
test "opaque keys never collide through delimiter concatenation" {
  let rows = aggregate(config(Session(gap=2)), [
    { id: "x", key: "a:0", at: 0, value: 1, },
    { id: "y", key: "a", at: 0, value: 2, },
    { id: "z", key: "a\u0000", at: 0, value: 3, },
  ])
  assert_eq(rows.length(), 3)
  assert_eq(rows[0].sum, 2L)
}

///|
test "session sweep agrees with independent graph connectivity oracle" {
  let c = config(Session(gap=4))
  for mask in 1..<256 {
    let events = []
    for i in 0..<8 {
      if ((mask >> i) & 1) == 1 {
        events.push(Event::{ id: i.to_string(), key: "k", at: i * 2, value: i, })
      }
    }
    let labels = Array::makei(events.length(), i => i)
    for _ in 0..<events.length() {
      for i in 0..<events.length() {
        for j in 0..<events.length() {
          if (events[i].at - events[j].at).abs() < 4 {
            let low = if labels[i] < labels[j] { labels[i] } else { labels[j] }
            labels[i] = low
            labels[j] = low
          }
        }
      }
    }
    let actual = aggregate(c, events)
    for i in 0..<events.length() {
      for j in 0..<events.length() {
        let together = actual.any(row => {
          row.members.contains(events[i].id) &&
          row.members.contains(events[j].id)
        })
        assert_eq(together, labels[i] == labels[j])
      }
    }
  }
}
