///|
test "all valid configurations have a representable finalization horizon" {
  let c = config(Session(gap=500000000), lateness=500000000)
  let e = Engine::new(c)
  ignore(e.apply(tx("a", [Put(sample("a", 1000000000))])))
  ignore(e.apply(Advance(id="w", to=2000000000)))
  assert_eq(e.rows()[0].phase, "final")
  assert_true(
    try {
      ignore(config(Session(gap=1000000000), lateness=1))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "same-time members remain separate facts and insertion order is irrelevant" {
  let c = config(Session(gap=1))
  let a = sample("a", 0, value=-3)
  let b = sample("b", 0, value=7)
  let rows = aggregate(c, [a, b])
  assert_true(aggregate(c, [b, a]) == rows)
  assert_eq(rows[0].count, 2)
  assert_eq(rows[0].sum, 4L)
  assert_eq(rows[0].min, -3)
  assert_eq(rows[0].max, 7)
}

///|
test "empty aggregate and finalizing empty state remain well-defined" {
  assert_eq(aggregate(config(Session(gap=1)), []).length(), 0)
  let e = Engine::new(config(Tumbling(size=10, offset=0)))
  assert_eq(e.apply(Advance(id="w", to=100)).status, "accepted")
  assert_eq(e.rows().length(), 0)
  assert_eq(e.apply(tx("late", [Put(sample("old", 0))])).status, "rejected")
}

///|
test "identical finalized put is a harmless committed no-op" {
  let e = Engine::new(config(Session(gap=2)))
  let a = sample("a", 0)
  ignore(e.apply(tx("a", [Put(a)])))
  ignore(e.apply(Advance(id="w", to=2)))
  let outcome = e.apply(tx("noop", [Put(a)]))
  assert_eq(outcome.status, "accepted")
  assert_eq(outcome.deltas.length(), 0)
  assert_eq(outcome.version, 3)
}

///|
test "whole transaction is rejected if only one sliding membership is final" {
  let e = Engine::new(config(Sliding(size=10, slide=5, offset=0)))
  ignore(e.apply(tx("a", [Put(sample("a", 6))])))
  ignore(e.apply(Advance(id="w", to=10)))
  assert_eq(e.rows()[0].phase, "final")
  assert_eq(e.rows()[1].phase, "open")
  let original = e.checkpoint()
  assert_eq(
    e.apply(tx("correct", [Put(sample("a", 7, value=2))])).status,
    "rejected",
  )
  assert_eq(e.checkpoint(), original)
}

///|
test "late session bridge cannot reopen a finalized component" {
  let e = Engine::new(config(Session(gap=10), lateness=5))
  ignore(e.apply(tx("seed", [Put(sample("a", 0)), Put(sample("c", 16))])))
  ignore(e.apply(Advance(id="w", to=15)))
  assert_eq(e.apply(tx("bridge", [Put(sample("b", 8))])).status, "rejected")
  assert_eq(e.rows().length(), 2)
}

///|
test "cross-key replacement retracts old aggregate and creates the new one" {
  let e = Engine::new(config(Session(gap=5)))
  ignore(e.apply(tx("a", [Put(sample("a", 0, key="old"))])))
  let o = e.apply(tx("move", [Put(sample("a", 20, key="new", value=-4))]))
  assert_eq(o.deltas.length(), 2)
  assert_eq(o.deltas[0].kind, "delete")
  assert_eq(e.rows()[0].key, "new")
  assert_eq(e.rows()[0].sum, -4L)
}

///|
test "transaction duplicate event IDs fail instead of depending on array order" {
  let e = Engine::new(config(Session(gap=5)))
  let o = e.apply(tx("bad", [Put(sample("a", 0)), Remove("a")]))
  assert_eq(o.status, "rejected")
  assert_eq(e.events().length(), 0)
  assert_eq(e.version(), 0)
}

///|
test "atomic replacement may avoid transient premature finalization" {
  let e = Engine::new(config(Session(gap=10)))
  ignore(
    e.apply(
      tx("seed", [
        Put(sample("a", 0)),
        Put(sample("b", 8)),
        Put(sample("c", 16)),
      ]),
    ),
  )
  ignore(e.apply(Advance(id="w", to=15)))
  assert_eq(e.apply(tx("bad", [Remove("b")])).status, "rejected")
  assert_eq(
    e.apply(tx("good", [Remove("b"), Put(sample("replacement", 9))])).status,
    "accepted",
  )
  assert_eq(e.rows().length(), 1)
  assert_eq(e.rows()[0].members, ["a", "c", "replacement"])
}

///|
test "malformed JSON and empty transactions are protocol failures" {
  for
    source in [
      "null", "{}", "[1]", "[{}]", "[{\"kind\":\"transaction\",\"id\":\"x\",\"changes\":[]}]",
      "[{\"kind\":\"watermark\",\"id\":\"w\",\"to\":null}]", "[{\"kind\":\"watermark\",\"id\":\"w\",\"to\":1,\"changes\":[]}]",
    ] {
    assert_true(
      try {
        ignore(decode_commands(source))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "strict parser limits nesting before domain inspection" {
  let source = "[".repeat(30) + "0" + "]".repeat(30)
  assert_true(
    try {
      ignore(strict_json(source))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "event and key validation also protect callers of the typed API" {
  for
    event in [
      sample("", 0),
      sample("a", -1),
      sample("a", 1000000001),
      sample("a", 0, value=-1000000001),
      sample("a", 0, key=""),
    ] {
    assert_true(
      try {
        ignore(aggregate(config(Session(gap=1)), [event]))
        false
      } catch {
        _ => true
      },
    )
  }
}
