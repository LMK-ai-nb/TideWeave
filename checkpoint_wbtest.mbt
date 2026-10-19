///|
test "checkpoint roundtrip retains rows, watermark, version and deduplication" {
  let e = Engine::new(config(Session(gap=10), lateness=20))
  let cmd = tx("seed", [Put(sample("a", 0)), Put(sample("c", 16))])
  ignore(e.apply(cmd))
  ignore(e.apply(tx("merge", [Put(sample("b", 8))])))
  ignore(e.apply(Advance(id="watermark", to=30)))
  let restored = restore(e.checkpoint())
  assert_true(restored.rows() == e.rows())
  assert_true(restored.events() == e.events())
  assert_eq(restored.version(), 3)
  assert_eq(restored.watermark(), 30)
  assert_eq(restored.apply(cmd).status, "duplicate")
  let split = tx("split", [Remove("b")])
  assert_true(restored.apply(split) == e.apply(split))
  assert_eq(restored.checkpoint(), e.checkpoint())
}

///|
test "checkpoint rejects forged counters and invalid replay histories" {
  let e = Engine::new(config(Session(gap=10)))
  ignore(e.apply(tx("seed", [Put(sample("a", 0))])))
  let original = obj(strict_json(e.checkpoint()))
  original["version"] = Json::number(99)
  let bad = Json::object(original).stringify()
  assert_true(
    try {
      ignore(restore(bad))
      false
    } catch {
      _ => true
    },
  )
  let original = obj(strict_json(e.checkpoint()))
  original["commands"] = @json.to_json([tx("bad", [Remove("missing")])])
  assert_true(
    try {
      ignore(restore(Json::object(original).stringify()))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "checkpoint suffix processing agrees with uninterrupted replay" {
  let c = config(Sliding(size=10, slide=5, offset=2), lateness=15)
  let prefix = [tx("a", [Put(sample("a", 0))]), tx("b", [Put(sample("b", 7))])]
  let suffix = [
    tx("c", [Put(sample("a", 4, value=-1))]),
    Advance(id="w", to=30),
  ]
  let e = Engine::new(c)
  ignore(e.run(prefix))
  let resumed = restore(e.checkpoint()).run(suffix)
  let full = e.run(suffix)
  assert_true(resumed.rows == full.rows)
  assert_true(resumed.steps == full.steps)
  assert_true(resumed.checkpoint == full.checkpoint)
}
