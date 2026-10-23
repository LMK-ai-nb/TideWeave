///|
fn main {
  let c = @tide.config(@tide.Session(gap=10), lateness=20) catch {
    _ => abort("invalid demo configuration")
  }
  let e = @tide.Engine::new(c) catch { _ => abort("cannot initialize demo") }
  let commands : Array[@tide.Command] = [
    @tide.Transact(id="seed", changes=[
      @tide.Put({ id: "left", key: "device-A", at: 0, value: 20, }),
      @tide.Put({ id: "right", key: "device-A", at: 16, value: 35, }),
    ]),
    @tide.Transact(id="late-bridge", changes=[
      @tide.Put({ id: "bridge", key: "device-A", at: 8, value: 12, }),
    ]),
    @tide.Transact(id="retract-bridge", changes=[@tide.Remove("bridge")]),
    @tide.Advance(id="finalize", to=60),
    @tide.Transact(id="blocked-correction", changes=[@tide.Remove("left")]),
    @tide.Forget(id="freeze", to=60),
    @tide.Transact(id="sealed-correction", changes=[@tide.Remove("left")]),
  ]
  for c in commands {
    let o = e.apply(c)
    println(
      "\{o.id}: \{o.status}; deltas=\{o.deltas.length()}; rows=\{e.rows().length()}",
    )
  }
  println("frozen=\{e.frozen_count()}, active=\{e.events().length()}")
  let restored = @tide.restore(e.checkpoint()) catch {
    _ => abort("checkpoint restore failed")
  }
  println(
    "restored version=\{restored.version()}, watermark=\{restored.watermark()}",
  )
}
