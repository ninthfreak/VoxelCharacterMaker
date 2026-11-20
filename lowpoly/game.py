"""What lowpoly/ takes from the game, so that nothing here is a second copy of it: the starter wardrobe, the test
poses, and every special shape's settings with their defaults. dump_wardrobe.gd writes them as JSON into
lowpoly/_work/ (which is not committed); that needs Godot: GODOT=/path/to/godot, or `godot` on PATH.
"""
import json, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WORK = os.path.join(HERE, "_work")
WARDROBE = os.path.join(WORK, "starter_wardrobe.json")
TABLES = os.path.join(WORK, "game_tables.json")


def available():
    return (os.path.exists(WARDROBE) and os.path.exists(TABLES)) or bool(os.environ.get("GODOT") or shutil.which("godot"))


def _dump():
    godot = os.environ.get("GODOT") or shutil.which("godot")
    if not godot:
        sys.exit("needs the game's tables in lowpoly/_work/. Write them with dump_wardrobe.gd (see its first lines), or set GODOT=/path/to/godot")
    os.makedirs(WORK, exist_ok=True)
    subprocess.run([godot, "--headless", "--path", ROOT, "--script", os.path.join(HERE, "dump_wardrobe.gd"), "--",
                    "--out", WARDROBE, "--tables", TABLES], check=True, stdout=subprocess.DEVNULL)


def wardrobe_path(fresh=False):
    if fresh or not (os.path.exists(WARDROBE) and os.path.exists(TABLES)): _dump()
    return WARDROBE


def tables(fresh=False):
    if fresh or not (os.path.exists(WARDROBE) and os.path.exists(TABLES)): _dump()
    return json.load(open(TABLES))
