#!/usr/bin/env python3
"""Compile the suite and run mocked UI/core regressions with native Luau CLIs."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--luau', default='luau')
parser.add_argument('--compiler', default='luau-compile')
args = parser.parse_args()
sources = sorted(ROOT.glob('src/**/*.luau')) + [ROOT / 'init.luau', ROOT / 'loader.luau']
subprocess.run([args.compiler, '--null', *map(str, sources)], check=True)
modules = []
for path in sources:
    content = path.read_text()
    delimiter = '='
    while f']{delimiter}]' in content:
        delimiter += '='
    modules.append(f'["{path.relative_to(ROOT).as_posix()}"] = [{delimiter}[{content}]{delimiter}],')
tests = '\n'.join(
    (ROOT / name).read_text()
    for name in ('tests/ui_motion.luau', 'tests/core_lifecycle.luau', 'tests/all_off.luau')
)
with tempfile.TemporaryDirectory(prefix='b0xaz-ui-') as directory:
    test = Path(directory) / 'ui_tests.luau'
    test.write_text('local SOURCES = {\n' + '\n'.join(modules) + '\n}\n' + tests)
    subprocess.run([args.luau, str(test)], check=True)
