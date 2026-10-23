///|
test "stream_json emits one outcome per command and a final summary" {
  let source = "{\"schema_version\":1,\"config\":{\"window\":{\"kind\":\"session\",\"gap\":10},\"lateness\":20}}\n" +
    "{\"id\":\"seed\",\"kind\":\"transaction\",\"changes\":[{\"op\":\"put\",\"event\":{\"id\":\"a\",\"key\":\"k\",\"at\":0,\"value\":3}}]}\n" +
    "{\"id\":\"w\",\"kind\":\"watermark\",\"to\":10}\n"
  let lines = stream_json(source).split("\n").map(l => l.to_owned()).collect()
  assert_eq(lines.length(), 3)
  assert_eq(str(req(obj(strict_json(lines[0])), "status")), "accepted")
  assert_eq(str(req(obj(strict_json(lines[1])), "status")), "accepted")
  let summary = obj(req(obj(strict_json(lines[2])), "summary"))
  assert_eq(integer(req(summary, "version")), 2)
  assert_eq(integer(req(summary, "watermark")), 10)
}

///|
test "stream_json rejects a malformed command line atomically" {
  let source = "{\"config\":{\"window\":{\"kind\":\"session\",\"gap\":5}}}\n" +
    "{\"id\":\"ok\",\"kind\":\"transaction\",\"changes\":[{\"op\":\"put\",\"event\":{\"id\":\"a\",\"key\":\"k\",\"at\":0,\"value\":1}}]}\n" +
    "{\"kind\":\"nope\"}\n"
  assert_true(
    try {
      ignore(stream_json(source))
      false
    } catch {
      _ => true
    },
  )
}
