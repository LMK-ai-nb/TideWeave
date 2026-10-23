///|
test "forget seals finalized facts and removes them from the active set" {
  let e = Engine::new(config(Tumbling(size=10, offset=0), lateness=0))
  ignore(e.apply(tx("seed", [Put(sample("a", 1)), Put(sample("b", 2))])))
  ignore(e.apply(Advance(id="w", to=10)))
  assert_eq(e.rows()[0].phase, "final")
  ignore(e.apply(Forget(id="f", to=10)))
  assert_eq(e.frozen_count(), 2)
  assert_eq(e.events().length(), 0)
  assert_false(e.correctable("a"))
  assert_eq(e.apply(tx("bad", [Remove("a")])).status, "rejected")
  assert_eq(
    e.apply(tx("bad2", [Put(sample("a", 1, value=9))])).status,
    "rejected",
  )
}

///|
test "forget keeps non-final windows active and correctable" {
  let e = Engine::new(config(Sliding(size=10, slide=5, offset=0), lateness=0))
  ignore(e.apply(tx("seed", [Put(sample("a", 6))])))
  ignore(e.apply(Advance(id="w", to=5)))
  ignore(e.apply(Forget(id="f", to=5)))
  assert_eq(e.frozen_count(), 0)
  assert_eq(e.events().length(), 1)
  assert_eq(
    e.apply(tx("correct", [Put(sample("a", 6, value=3))])).status,
    "accepted",
  )
}

///|
test "forget is journaled and replayable through checkpoint restore" {
  let e = Engine::new(config(Session(gap=10), lateness=0))
  ignore(e.apply(tx("seed", [Put(sample("a", 0))])))
  ignore(e.apply(Advance(id="w", to=10)))
  ignore(e.apply(Forget(id="f", to=10)))
  let restored = restore(e.checkpoint())
  assert_eq(restored.frozen_count(), 1)
  assert_eq(restored.events().length(), 0)
  assert_eq(restored.apply(tx("bad", [Remove("a")])).status, "rejected")
}

///|
test "forget frees active event capacity for new arrivals" {
  let e = Engine::new(config(Session(gap=10), max_events=1, lateness=0))
  ignore(e.apply(tx("seed", [Put(sample("a", 0))])))
  ignore(e.apply(Advance(id="w", to=10)))
  ignore(e.apply(Forget(id="f", to=10)))
  assert_eq(e.frozen_count(), 1)
  assert_eq(e.apply(tx("new", [Put(sample("b", 20))])).status, "accepted")
  assert_eq(e.events().length(), 1)
}

///|
test "forget command roundtrips through the wire format" {
  let commands = [Forget(id="f", to=25)]
  assert_true(decode_commands(@json.to_json(commands).stringify()) == commands)
}
