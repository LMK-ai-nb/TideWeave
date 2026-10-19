///|
fn sample(
  id : String,
  at : Int32,
  value~ : Int32 = 1,
  key~ : String = "k",
) -> Event {
  { id, at, value, key, }
}

///|
fn tx(id : String, changes : Array[Mutation]) -> Command {
  Transact(id~, changes~)
}

///|
test "merge and split emit a complete atomic materialized-view changelog" {
  let e = Engine::new(config(Session(gap=10), lateness=20))
  assert_eq(
    e.apply(tx("one", [Put(sample("a", 0)), Put(sample("c", 16))])).status,
    "accepted",
  )
  let merged = e.apply(tx("bridge", [Put(sample("b", 8))]))
  assert_eq(merged.deltas.length(), 3)
  assert_eq(merged.deltas[0].kind, "delete")
  assert_eq(merged.deltas[1].kind, "delete")
  assert_eq(merged.deltas[2].kind, "upsert")
  let split = e.apply(tx("split", [Remove("b")]))
  assert_eq(split.deltas.length(), 3)
  assert_eq(e.rows().length(), 2)
  assert_eq(e.version(), 3)
}

///|
test "watermark finalizes exactly at end plus lateness and protects all members" {
  let e = Engine::new(config(Tumbling(size=10, offset=0), lateness=5))
  ignore(e.apply(tx("a", [Put(sample("a", 1)), Put(sample("b", 2, value=2))])))
  assert_eq(e.apply(Advance(id="w1", to=14)).status, "accepted")
  assert_eq(e.rows()[0].phase, "closing")
  ignore(e.apply(Advance(id="w2", to=15)))
  assert_eq(e.rows()[0].phase, "final")
  let before = e.rows()
  assert_eq(
    e.apply(tx("bad", [Put(sample("a", 1, value=2)), Put(sample("b", 2))])).status,
    "rejected",
  )
  assert_true(e.rows() == before)
  assert_eq(e.apply(tx("late", [Put(sample("c", 1))])).status, "rejected")
  assert_eq(e.apply(Advance(id="back", to=14)).status, "rejected")
  assert_eq(e.version(), 3)
}

///|
test "transaction rollback spans keys and rejects missing removes" {
  let e = Engine::new(config(Session(gap=5), max_events=2))
  ignore(e.apply(tx("a", [Put(sample("a", 1))])))
  let before = e.events()
  assert_eq(
    e.apply(tx("bad", [Put(sample("b", 2)), Remove("missing")])).status,
    "rejected",
  )
  assert_true(e.events() == before)
  assert_eq(e.apply(tx("bad", [Put(sample("b", 2))])).status, "accepted")
  assert_eq(e.apply(tx("full", [Put(sample("c", 3))])).status, "rejected")
  assert_eq(
    e.apply(tx("replace", [Remove("a"), Put(sample("c", 3, key="new"))])).status,
    "accepted",
  )
  assert_eq(e.events().length(), 2)
}

///|
test "successful idempotency survives no-op commands and conflicting retries" {
  let e = Engine::new(config(Session(gap=5), max_operations=1))
  let c = tx("id", [Put(sample("a", 1))])
  assert_eq(e.apply(c).status, "accepted")
  assert_eq(e.apply(c).status, "duplicate")
  assert_eq(e.apply(tx("id", [Put(sample("a", 2))])).status, "conflict")
  assert_eq(e.apply(Advance(id="full", to=10)).status, "rejected")
  assert_eq(e.version(), 1)
}

///|
test "caller mutation cannot corrupt internal rows or remembered commands" {
  let e = Engine::new(config(Session(gap=5)))
  let changes = [Put(sample("a", 1))]
  let outcome = e.apply(tx("id", changes))
  changes.push(Remove("a"))
  let rows = e.rows()
  rows[0].members.push("injected")
  if outcome.deltas[0].after is Some(row) {
    row.members.push("also injected")
  }
  assert_eq(e.rows()[0].members, ["a"])
  assert_eq(e.apply(tx("id", [Put(sample("a", 1))])).status, "duplicate")
}

///|
test "session split that creates an expired historical component is rejected" {
  let e = Engine::new(config(Session(gap=10), lateness=0))
  ignore(
    e.apply(
      tx("all", [Put(sample("a", 0)), Put(sample("b", 8)), Put(sample("c", 16))]),
    ),
  )
  ignore(e.apply(Advance(id="w", to=15)))
  assert_eq(e.rows()[0].phase, "open")
  assert_eq(e.apply(tx("split", [Remove("b")])).status, "rejected")
  assert_eq(e.rows()[0].members, ["a", "b", "c"])
}
