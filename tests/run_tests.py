"""Run the addon's real Lua 5.1 code; WoW boundary fixtures are not live-client tests."""
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'deps'))
from lupa.lua51 import LuaRuntime

files = [root / 'tests' / x for x in sys.argv[1:]] if len(sys.argv) > 1 else sorted((root / 'tests').glob('test_*.lua'))
failures = 0
for path in files:
    lua = LuaRuntime(unpack_returned_tuples=True)
    addon_dir = root / 'bjarkiCC' if (root / 'bjarkiCC').is_dir() else root
    lua.globals().ADDON_DIR = addon_dir.as_posix()
    try:
        lua.execute(path.read_text(encoding='utf-8'))
        print('PASS', path.name, flush=True)
    except Exception as exc:
        failures += 1
        print('FAIL', path.name, exc, flush=True)
sys.exit(bool(failures))
