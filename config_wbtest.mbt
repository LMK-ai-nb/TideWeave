///|
test "configuration accepts valid fixed and session specifications" {
  let a = config(Tumbling(size=10, offset=0))
  assert_eq(a.lateness, 0)
  let b = config(Sliding(size=11, slide=3, offset=2), lateness=5)
  assert_eq(b.max_events, 5000)
  let c = config(Session(gap=1), max_operations=1)
  assert_eq(c.max_operations, 1)
}

///|
test "configuration rejects ambiguous and explosive assignments" {
  for
    w in [
      Tumbling(size=0, offset=0),
      Tumbling(size=3, offset=3),
      Sliding(size=65, slide=1, offset=0),
      Sliding(size=3, slide=4, offset=0),
      Sliding(size=4, slide=2, offset=-1),
      Session(gap=0),
    ] {
    let rejected = try {
      ignore(config(w))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
