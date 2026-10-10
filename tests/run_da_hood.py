"""Run Da Hood speed-macro behavior tests with a Luau CLI executable.

Usage: python3 tests/run_da_hood.py /path/to/luau
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "src/Plugins/DaHood/SpeedMacroService.luau").read_text()
spec = (root / "tests/DaHoodSpeedMacro.spec.luau").read_text()
assert spec.count("__SERVICE__") == 1
spec = spec.replace("__SERVICE__", "(function()\n" + source + "\nend)()")
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "DaHoodSpeedMacro.test.luau"
    path.write_text(spec)
    subprocess.run([sys.argv[1], str(path)], check=True)
