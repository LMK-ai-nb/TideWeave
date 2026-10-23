///|
test "count trigger marks a window closing before the watermark reaches it" {
  let e = Engine::new(
    config(Tumbling(size=10, offset=0), trigger=Count(threshold=2)),
  )
  ignore(e.apply(tx("a", [Put(sample("a", 1)), Put(sample("b", 2))])))
  assert_eq(e.rows()[0].phase, "closing")
  assert_eq(e.rows()[0].count, 2)
  // Early-fired (closing) windows remain correctable until final.
  assert_eq(e.apply(tx("c", [Put(sample("c", 3))])).status, "accepted")
}

///|
test "watermark trigger preserves the original open/closing boundary" {
  let e = Engine::new(config(Tumbling(size=10, offset=0), lateness=5))
  ignore(e.apply(tx("a", [Put(sample("a", 1)), Put(sample("b", 2))])))
  assert_eq(e.rows()[0].phase, "open")
  ignore(e.apply(Advance(id="w", to=10)))
  assert_eq(e.rows()[0].phase, "closing")
  ignore(e.apply(Advance(id="w2", to=15)))
  assert_eq(e.rows()[0].phase, "final")
}

///|
test "trigger serialization roundtrips and rejects invalid thresholds" {
  for t in [Watermark, Count(threshold=3)] {
    let c = config(Session(gap=5), trigger=t)
    assert_true(decode_config(c.to_json().stringify()) == c)
  }
  assert_true(
    try {
      ignore(config(Session(gap=5), trigger=Count(threshold=0)))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "trigger JSON is optional and defaults to watermark" {
  let c = decode_config(
    "{\"window\":{\"kind\":\"session\",\"gap\":5},\"trigger\":{\"kind\":\"count\",\"threshold\":2}}",
  )
  assert_true(c.trigger == Count(threshold=2))
  let d = decode_config("{\"window\":{\"kind\":\"session\",\"gap\":5}}")
  assert_true(d.trigger == Watermark)
}
