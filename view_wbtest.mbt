///|
test "guarded downstream view follows merge, split, finality and duplicate delivery" {
  let engine = Engine::new(config(Session(gap=10), lateness=20))
  let view = View::new()
  let commands = [
    tx("seed", [Put(sample("a", 0)), Put(sample("c", 16))]),
    tx("bridge", [Put(sample("b", 8))]),
    tx("split", [Remove("b")]),
    Advance(id="w", to=100),
    tx("denied", [Remove("a")]),
    tx("split", [Remove("b")]),
  ]
  for cmd in commands {
    let outcome = engine.apply(cmd)
    view.apply(outcome)
    view.apply(outcome)
    assert_true(view.rows() == engine.rows())
    assert_eq(view.version(), engine.version())
  }
}

///|
test "view rejects omitted outcomes and rolls back invalid before-images" {
  let engine = Engine::new(config(Session(gap=10)))
  let first = engine.apply(tx("a", [Put(sample("a", 0))]))
  let second = engine.apply(tx("b", [Put(sample("b", 8))]))
  let view = View::new()
  assert_true(
    try {
      view.apply(second)
      false
    } catch {
      _ => true
    },
  )
  assert_eq(view.version(), 0)
  view.apply(first)
  let before = view.rows()
  let bad_delta = Delta::{
    kind: "upsert",
    before: None,
    after: second.deltas[0].after,
  }
  let bad = { ..second, deltas: [bad_delta], }
  assert_true(
    try {
      view.apply(bad)
      false
    } catch {
      _ => true
    },
  )
  assert_true(view.rows() == before)
  view.apply(second)
  assert_true(view.rows() == engine.rows())
}

///|
test "stateful mixed-key differential trace mirrors batch and downstream state" {
  let c = config(Sliding(size=13, slide=5, offset=3), lateness=1000)
  let engine = Engine::new(c)
  let view = View::new()
  let expected : Map[String, Event] = Map([])
  for i in 0..<180 {
    let id = (i % 17).to_string()
    let command = if i % 5 == 4 && expected.contains(id) {
      expected.remove(id)
      tx(i.to_string(), [Remove(id)])
    } else {
      let e = sample(id, i * 37 % 100, key=(i % 3).to_string(), value=i - 90)
      expected[id] = e
      tx(i.to_string(), [Put(e)])
    }
    let outcome = engine.apply(command)
    assert_eq(outcome.status, "accepted")
    view.apply(outcome)
    let events = []
    for _, e in expected {
      events.push(e)
    }
    assert_true(aggregate(c, events) == engine.rows())
    assert_true(view.rows() == engine.rows())
  }
}
