"""Check that Moon's published archive contains neither local secrets nor build output."""
import json, pathlib, subprocess, zipfile
root = pathlib.Path(__file__).resolve().parent.parent
subprocess.run(["moon", "package"], cwd=root, check=True)
archives = list((root / "_build" / "publish").glob("*.zip"))
assert archives, "moon package did not produce an archive"
archive = max(archives, key=lambda p:p.stat().st_mtime)
with zipfile.ZipFile(archive) as z:
    names = z.namelist()
    for name in names:
        segments = pathlib.PurePosixPath(name).parts
        assert not any(p in {"work", "deliverables", ".git", "dist", "artifacts", "_build", "credentials.json", "engine.js"} for p in segments), name
    assert any(n.endswith("LICENSE") for n in names)
    assert any(n.endswith("engine.mbt") for n in names)
    assert any(n.endswith("docs/SEMANTICS.md") for n in names)
print(json.dumps({"archive":archive.name,"files":len(names),"checked":"no work, credentials, private deliverables or generated engines"}))
