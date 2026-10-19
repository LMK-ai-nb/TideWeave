///|
test "wire format roundtrips all typed commands and window configurations" {
  for
    c in [
      config(Session(gap=5)),
      config(Tumbling(size=10, offset=2)),
      config(Sliding(size=10, slide=3, offset=2)),
    ] {
    assert_true(decode_config(c.to_json().stringify()) == c)
  }
  let commands = [
    tx("one", [Put(sample("a", 1, value=-7)), Remove("other")]),
    Advance(id="w", to=25),
  ]
  assert_true(decode_commands(@json.to_json(commands).stringify()) == commands)
}

///|
test "wire rejects duplicate decoded keys, misspellings, fractions and rounding" {
  for
    source in [
      "{\"window\":{\"kind\":\"session\",\"gap\":5},\"lateness\":0,\"late\\u006eess\":1}",
      "{\"window\":{\"kind\":\"session\",\"gap\":5,\"slide\":2}}", "{\"window\":{\"kind\":\"session\",\"gap\":5.00000000000000001}}",
      "{\"window\":{\"kind\":\"session\",\"gap\":5e0}}", "{\"window\":{\"kind\":\"session\",\"gap\":1e-999}}",
      "{\"window\":{\"kind\":\"session\",\"gap\":50000000000}}", "{\"window\":{\"kind\":\"session\",\"gap\":5},\"latenes\":0}",
    ] {
    let rejected = try {
      ignore(decode_config(source))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "protocol errors are distinguished from atomic business rejections" {
  let source = "{\"schema_version\":1,\"config\":{\"window\":{\"kind\":\"session\",\"gap\":5}},\"commands\":[{\"kind\":\"transaction\",\"id\":\"bad\",\"changes\":[{\"op\":\"remove\",\"event_id\":\"unknown\"}]}]}"
  let report = strict_json(replay_json(source))
  let steps = arr(req(obj(report), "steps"), 10)
  assert_eq(str(req(obj(steps[0]), "status")), "rejected")
}
