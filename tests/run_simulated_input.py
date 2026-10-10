"""Check that the suite simulates input instead of injecting it, then run the behavior spec.

Usage:
    python3 tests/run_simulated_input.py            # static policy scan only
    python3 tests/run_simulated_input.py /path/to/luau   # policy scan + spec
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]

# Anything that reaches the operating system's input queue, or Roblox's own virtual input
# manager, counts as hijacking the player's controls: it can land on the menu, on another
# window, or on whatever the player is holding.
BANNED = (
    "mouse1click", "mouse1press", "mouse1release", "mouse2click",
    "mousebutton1click", "mousebutton2click", "mousemoverel", "mousemoveto",
    "keypress", "keytap", "keydown", "keyup",
    "VirtualInputManager", "SendKeyEvent", "SendMouseButtonEvent", "SendMouseMoveEvent",
)

REQUIRED = {
    "src/Core/Environment.luau": ("function Environment:ActivateTool", "GetEquippedTool"),
    "src/Combat/TriggerbotService.luau": ("environment:ActivateTool()",),
    "src/Plugins/MurderersVsSheriffs/AttackService.luau": ("Environment:ActivateTool(",),
}


def sources():
    files = [root / "init.luau", root / "loader.luau"]
    files.extend(sorted((root / "src").rglob("*.luau")))
    return files


def scan():
    failures = []
    for path in sources():
        text = path.read_text()
        relative = path.relative_to(root)
        for token in BANNED:
            if token in text:
                failures.append(f"{relative}: injects real input ({token})")
        for needle in REQUIRED.get(str(relative).replace("\\", "/"), ()):
            if needle not in text:
                failures.append(f"{relative}: missing the simulated path ({needle})")
    return failures


def run_spec(luau):
    environment = (root / "src/Core/Environment.luau").read_text()
    triggerbot = (root / "src/Combat/TriggerbotService.luau").read_text()
    spec = (root / "tests/SimulatedInput.spec.luau").read_text()
    for marker, source in (("__ENVIRONMENT__", environment), ("__TRIGGERBOT__", triggerbot)):
        assert spec.count(marker) == 1, f"spec needs exactly one {marker}"
        spec = spec.replace(marker, "(function()\n" + source + "\nend)()")
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "SimulatedInput.test.luau"
        path.write_text(spec)
        subprocess.run([luau, str(path)], check=True)


failures = scan()
for failure in failures:
    print(f"FAIL {failure}")
assert not failures, "no feature may inject real input"
print("Input policy scan passed: no injected clicks, keys, or cursor moves")

if len(sys.argv) > 1:
    run_spec(sys.argv[1])
