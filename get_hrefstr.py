#!/usr/bin/env python3
"""Read the XMU sports H5 `hrefstr` from the local WeChat WebView LocalStorage.

The hrefstr carries the current business identity (uid/token/sign/...).  This
tool extracts it without touching the network and without writing anything to
disk; the value is printed to stdout only.  Works on macOS (verified) and
Windows (via --db/--profile, or a best-effort unverified auto-search).

Stdlib only; bundles a pure-Python LevelDB reader from CCL Forensics (MIT),
kept under _vendor/ with its license files.

Typical use:
    python3 get_hrefstr.py                 # auto-locate and print hrefstr
    python3 get_hrefstr.py --profile DIR   # explicit WeChat webview profile dir
    python3 get_hrefstr.py --db DIR        # explicit leveldb dir (contains CURRENT)
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import re
import subprocess
import sys
from pathlib import Path

# Make `_vendor` importable regardless of the current working directory.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _vendor.ccl_leveldb as leveldb  # noqa: E402

ORIGIN = "https://xdty.xmu.edu.cn"
APPID = "wx81a2b2fa90759cb7"
DB_SUBDIR = Path("Local Storage") / "leveldb"

MAC_BASE = Path.home() / "Library/Containers/com.tencent.xinWeChat/Data/Documents/app_data/radium"


class HrefstrError(RuntimeError):
    """A user-facing, credential-free explanation of why hrefstr is unavailable."""


def _log(msg: str) -> None:
    print(msg, file=sys.stderr)


def _decode_string(raw: bytes) -> str:
    # Chromium's LocalStorage type marker decides the encoding: 0x00 -> UTF-16LE,
    # 0x01 -> latin-1.  Do not guess or round-trip encodings.
    if raw and raw[0] == 0:
        return raw[1:].decode("utf-16-le")
    if raw and raw[0] == 1:
        return raw[1:].decode("latin-1")
    raise HrefstrError("unsupported LocalStorage string format")


def read_origin_keys(db: Path, origin: str = ORIGIN) -> dict:
    """Return {'hrefstr': str|None, 'is_new_ajax_res': bool} for one leveldb dir.

    Mirrors the read-only, damage-checking, concurrent-modification-checking
    logic already proven in the upper project's api/auth.py.
    """
    if not db.is_dir() or not (db / "CURRENT").is_file():
        raise HrefstrError(f"不是有效的 LevelDB 目录（缺 CURRENT）：{db}")

    logging.getLogger(leveldb.__name__).disabled = True
    current = (db / "CURRENT").read_text().strip()
    if not re.fullmatch(r"MANIFEST-[0-9]+", current):
        raise HrefstrError("无法识别 LevelDB 清单（CURRENT 格式不符）")

    manifest_path = db / current
    manifest_stamp = manifest_path.stat().st_mtime_ns
    manifest = leveldb.ManifestFile(manifest_path)
    live_tables: set = set()
    log_number = None
    previous_log = 0
    try:
        for edit in manifest:
            for item in edit.deleted_files:
                live_tables.discard(item.file_no)
            for item in edit.new_files:
                live_tables.add(item.file_no)
            if edit.log_number is not None:
                log_number = edit.log_number
            if edit.prev_log_number is not None:
                previous_log = edit.prev_log_number
        if manifest.damage or log_number is None:
            raise HrefstrError("LevelDB 清单不完整")
    finally:
        manifest.close()

    prefix = b"_" + origin.encode() + b"\x00"
    latest: dict = {}
    stamps: list = []
    for path in sorted(db.iterdir()):
        if not path.stem.isdigit():
            continue
        number = int(path.stem)
        if path.suffix in (".ldb", ".sst") and number in live_tables:
            reader = leveldb.LdbFile(path)
        elif path.suffix == ".log" and (number >= log_number or number == previous_log):
            reader = leveldb.LogFile(path)
        else:
            continue
        stat = path.stat()
        stamps.append((path, stat.st_size, stat.st_mtime_ns))
        try:
            for record in reader:
                key = record.user_key
                if not key.startswith(prefix):
                    continue
                try:
                    script_key = _decode_string(key[len(prefix):])
                except HrefstrError:
                    continue  # not a string we care about; skip safely
                if script_key not in ("hrefstr", "isNewAjaxRes"):
                    continue
                if script_key not in latest or record.seq > latest[script_key].seq:
                    latest[script_key] = record
            if reader.damage:
                raise HrefstrError("LevelDB 数据校验失败")
        finally:
            reader.close()

    # Re-read to detect concurrent writes by WeChat during our read.
    changed = (db / "CURRENT").read_text().strip() != current
    changed |= manifest_path.stat().st_mtime_ns != manifest_stamp
    changed |= any(
        (p.stat().st_size, p.stat().st_mtime_ns) != (size, mtime)
        for p, size, mtime in stamps
    )
    if changed:
        raise HrefstrError("读取期间微信存储发生变化；请退出微信或稍后重试")

    values = {
        key: _decode_string(record.value)
        for key, record in latest.items()
        if record.state == leveldb.KeyState.Live
    }
    return values


def extract_hrefstr(db: Path, origin: str = ORIGIN) -> str:
    values = read_origin_keys(db, origin)
    if values.get("isNewAjaxRes"):
        raise HrefstrError("当前为未实现的新版 h5_token 分支，无法读取旧版 hrefstr")
    if not values.get("hrefstr"):
        raise HrefstrError(
            "当前 Origin 没有有效 hrefstr。请先在微信中打开『厦大体育 → 场馆预约』后再试。"
        )
    return values["hrefstr"]


# --- locating the leveldb directory -------------------------------------------------

def _macos_profile_dirs() -> list[Path]:
    """All WeChat WebView profile dirs on macOS (deterministic; no ps/lsof)."""
    profiles = MAC_BASE / "web" / "profiles"
    if not profiles.is_dir():
        return []
    return [p for p in sorted(profiles.iterdir())
            if p.name.startswith(("webview_", "multitab_")) and p.is_dir()]


def _windows_search_bases() -> list[Path]:
    """Best-effort candidate bases for WeChat on Windows (UNVERIFIED here).

    WeChat 4.x (xwechat) mirrors the macOS layout; community reports point at
    %APPDATA%\\Tencent\\xwechat\\radium\\web\\profiles\\<uuid>\\Local Storage\\leveldb.
    These have not been confirmed on a real Windows box, so prefer --db/--profile.
    """
    bases: list[Path] = []
    appdata = os.environ.get("APPDATA")
    if appdata:
        bases += [
            Path(appdata) / "Tencent" / "xwechat" / "radium" / "web" / "profiles",
            Path(appdata) / "Tencent" / "xwechat" / "radium",
            Path(appdata) / "Tencent" / "WeChat",
        ]
    bases += [
        Path.home() / "Documents" / "WeChat Files",
        Path.home() / "Documents" / "xwechat_files",
    ]
    return bases


def _find_leveldb_dirs(bases: list[Path], max_depth: int = 3) -> list[Path]:
    """Search `bases` for leveldb dirs, returning every database exactly once.

    The Windows candidates overlap: `...\\radium` contains
    `...\\radium\\web\\profiles`, so walking both reports the same leveldb dir
    twice and the caller mistakes one profile for several (and bails out with
    "multiple profiles found").  Prune nested bases first, then drop repeated
    paths — symlinked layouts collapse to the same real path too.
    """
    roots: list[Path] = []
    for base in sorted(bases, key=lambda p: len(p.parts)):
        resolved = Path(os.path.realpath(base))
        if not resolved.is_dir():
            continue
        if any(resolved == root or root in resolved.parents for root in roots):
            continue
        roots.append(resolved)

    found: list[Path] = []
    seen: set = set()
    for base in roots:
        try:
            for root, dirs, _files in os.walk(base):
                rel = Path(root).relative_to(base)
                if len(rel.parts) > max_depth:
                    dirs[:] = []
                    continue
                candidate = Path(root) / DB_SUBDIR
                if not (candidate / "CURRENT").is_file():
                    continue
                key = os.path.realpath(candidate)
                if key in seen:
                    continue
                seen.add(key)
                found.append(candidate)
        except OSError:
            continue
    return found


def _locate_db_dirs() -> list[Path]:
    """All candidate leveldb dirs for the current platform, best-effort."""
    if sys.platform == "darwin":
        return [p / DB_SUBDIR for p in _macos_profile_dirs()]
    if sys.platform == "win32":
        return _find_leveldb_dirs(_windows_search_bases())
    # Generic fallback: a few common bases.
    return _find_leveldb_dirs([
        Path.home() / "Documents" / "WeChat Files",
        Path.home() / "Library/Containers/com.tencent.xinWeChat/Data/Documents/app_data/radium/web/profiles",
    ])


# --- CLI ----------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", help="直接指定 leveldb 目录（含 CURRENT 的目录）")
    ap.add_argument("--profile", help="指定 webview_xxx 或 multitab_xxx 配置目录")
    ap.add_argument("--origin", default=ORIGIN, help="要读取的 Origin（默认厦大体育）")
    ap.add_argument("--json", action="store_true", help="以 JSON 输出 hrefstr 与来源信息")
    ap.add_argument("--verbose", action="store_true", help="在 stderr 打印定位过程")
    args = ap.parse_args(argv)

    if args.db:
        db = Path(args.db)
        return _emit(db, args)

    if args.profile:
        db = Path(args.profile) / DB_SUBDIR
        return _emit(db, args)

    # Auto-locate.
    if args.verbose:
        _log("正在自动定位微信 WebView 的 Local Storage …")
    try:
        dirs = _locate_db_dirs()
    except PermissionError as exc:
        _log(f"无法访问微信 WebView 配置目录：{exc.filename}")
        return 2
    if args.verbose:
        _log(f"找到 {len(dirs)} 个候选目录。")

    matches: list[tuple[Path, str]] = []
    seen_dirs: set = set()
    for d in dirs:
        key = os.path.realpath(d)
        if key in seen_dirs:
            continue  # 同一个数据库被不同 base 搜到两次，只算一个候选
        seen_dirs.add(key)
        if args.verbose:
            _log(f"  候选: {d}")
        try:
            href = extract_hrefstr(d, args.origin)
        except HrefstrError as exc:
            if args.verbose:
                _log(f"    跳过：{exc}")
            continue
        matches.append((d, href))

    if len(matches) == 1:
        return _emit(matches[0][0], args)
    if len(matches) > 1:
        _log("找到多个含 hrefstr 的配置目录，请用 --profile 或 --db 指定其一：")
        for d, _href in matches:
            _log(f"  {d}")
        return 2

    _log("未能自动定位到含 hrefstr 的 Local Storage。")
    _log("请用 --verbose 查看候选和失败原因，或用 --db <leveldb目录> 显式指定。")
    _log("并确认已在微信中打开过『厦大体育 → 场馆预约』。")
    return 1


def _emit(db: Path, args) -> int:
    if args.verbose:
        _log(f"读取: {db}")
    try:
        href = extract_hrefstr(db, args.origin)
    except HrefstrError as exc:
        _log(f"读取失败：{exc}")
        return 1
    if args.json:
        print(json.dumps({"origin": args.origin, "hrefstr": href, "source_db": str(db)},
                         ensure_ascii=False))
    else:
        print(href)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
