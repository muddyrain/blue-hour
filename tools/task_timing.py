"""Explicit UTC stage intervals, not model thinking time. Python 3.10+, stdlib only."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PHASES = ("inspection", "implementation", "driver_precheck", "targeted_test",
          "final_check", "export_windows", "media", "handoff")
STATUSES = ("pass", "fail", "cancelled", "unknown")
LIMIT = 1024 * 1024


class TimingError(ValueError):
    pass


def task_id(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*", value) or len(value) > 64:
        raise TimingError("invalid task ID (uppercase letters, digits and hyphens)")


def output_path(root, out):
    root = Path(root).resolve()
    out = Path(out)
    path = out if out.is_absolute() else root / out
    allowed = root / ".local" / "task-timing"
    if ".." in path.parts or path.suffix.lower() != ".json" or not path.is_relative_to(allowed) or path == allowed:
        raise TimingError("output must be a JSON file under project .local/task-timing/")
    for part in [path, *path.parents]:
        try:
            info = part.lstat()
        except FileNotFoundError:
            continue
        if part.is_symlink() or getattr(info, "st_file_attributes", 0) & 0x400:
            raise TimingError("links and Windows reparse points are prohibited")
        if part == path and info.st_nlink > 1:
            raise TimingError("hardlinked records are prohibited")
        if part == root:
            break
    if not path.resolve().is_relative_to(allowed):
        raise TimingError("output escapes the timing namespace")
    return path


def instant(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z", value):
        raise TimingError("timestamps must be ISO 8601 UTC ending in Z")
    try:
        return datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise TimingError("invalid UTC timestamp") from error


def stamp(now=None):
    value = now if now is not None else datetime.now(timezone.utc)
    if value.tzinfo is None or value.utcoffset().total_seconds() != 0:
        raise TimingError("clock must be UTC")
    return value.isoformat(timespec="microseconds").replace("+00:00", "Z")


def reason_text(value):
    if not isinstance(value, str) or len(value) > 1000 or any(ord(c) < 32 for c in value):
        raise TimingError("reason must be a short single-line description")
    if re.search(r"(?i)\b[A-Z]:[\\/]|\\\\|/(?:Users|home)/|\b\S+@\S+\.\S+|github_pat_|ghp_|PRIVATE KEY", value):
        raise TimingError("reason must omit private paths, emails and credentials")


def validate(data):
    if not isinstance(data, dict) or set(data) != {"kind", "schema", "task", "events"}:
        raise TimingError("not a task timing record; existing file preserved")
    if data["kind"] != "blue-hour-task-timing" or type(data["schema"]) is not int or data["schema"] != 1:
        raise TimingError("unsupported timing record")
    task_id(data["task"])
    if not isinstance(data["events"], list):
        raise TimingError("invalid event list")
    active = set()
    fields = {"id", "phase", "started_at", "ended_at", "elapsed_seconds", "status", "reason"}
    for number, event in enumerate(data["events"], 1):
        if not isinstance(event, dict) or set(event) != fields or type(event["id"]) is not int or event["id"] != number:
            raise TimingError("invalid or duplicated event identity")
        if event["phase"] not in PHASES:
            raise TimingError("invalid phase")
        start = instant(event["started_at"])
        reason_text(event["reason"])
        if event["status"] == "running":
            if event["ended_at"] is not None or event["elapsed_seconds"] is not None or event["phase"] in active:
                raise TimingError("invalid running event")
            active.add(event["phase"])
        else:
            if event["status"] not in STATUSES:
                raise TimingError("invalid status")
            elapsed = round((instant(event["ended_at"]) - start).total_seconds(), 6)
            if elapsed < 0 or type(event["elapsed_seconds"]) not in (int, float) or event["elapsed_seconds"] != elapsed:
                raise TimingError("invalid elapsed interval")
            if event["status"] != "pass" and not event["reason"].strip():
                raise TimingError("failed/cancelled/unknown events require a reason")


def read_record(path):
    if not path.is_file() or path.stat().st_size > LIMIT:
        raise TimingError("missing or oversized timing record")
    raw = path.read_bytes()
    try:
        data = json.loads(raw.decode("utf-8"), parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
    except (ValueError, UnicodeError) as error:
        raise TimingError("invalid JSON; existing file preserved") from error
    validate(data)
    return data, raw


@contextmanager
def writer_lock(path):
    lock = path.with_name(path.name + ".lock")
    try:
        descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as error:
        raise TimingError("record busy; retry later, never remove an unknown lock") from error
    os.close(descriptor)
    try:
        yield
    finally:
        lock.unlink()


def save_record(path, data, before):
    validate(data)
    raw = (json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")
    if len(raw) > LIMIT:
        raise TimingError("timing record capacity reached; retain it and choose a new run path")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".timing-", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        if before is None:
            # Exclusive publication: an existing file can never become a fresh run.
            os.link(temporary, path)
        else:
            if path.read_bytes() != before:
                raise TimingError("record changed during update; original preserved")
            os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def update(root, out, task, phase, *, status=None, reason="", now=None):
    task_id(task)
    if phase not in PHASES:
        raise TimingError("invalid phase")
    reason_text(reason)
    if status is not None and (status not in STATUSES or (status != "pass" and not reason.strip())):
        raise TimingError("invalid status or missing failure reason (use UNKNOWN if undiagnosed)")
    path = output_path(root, out)
    path.parent.mkdir(parents=True, exist_ok=True)
    with writer_lock(path):
        data, before = read_record(path) if path.exists() else ({"kind": "blue-hour-task-timing", "schema": 1, "task": task, "events": []}, None)
        if data["task"] != task:
            raise TimingError("task mismatch; choose a new run path")
        running = [e for e in data["events"] if e["phase"] == phase and e["status"] == "running"]
        moment = stamp(now)
        if status is None:
            if running:
                raise TimingError("phase already running")
            event = {"id": len(data["events"]) + 1, "phase": phase, "started_at": moment,
                     "ended_at": None, "elapsed_seconds": None, "status": "running", "reason": reason}
            data["events"].append(event)
        else:
            if len(running) != 1:
                raise TimingError("phase not running (never started or already ended)")
            event = running[0]
            elapsed = round((instant(moment) - instant(event["started_at"])).total_seconds(), 6)
            if elapsed < 0:
                raise TimingError("UTC clock moved backwards; interval remains open/UNKNOWN")
            event.update(ended_at=moment, elapsed_seconds=elapsed, status=status, reason=reason)
        save_record(path, data, before)
    return event


def report(root, out):
    data, _ = read_record(output_path(root, out))
    intervals = sorted((instant(e["started_at"]), instant(e["ended_at"])) for e in data["events"] if e["ended_at"] is not None)
    merged = []
    for start, end in intervals:
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
        else:
            merged.append((start, end))
    coverage = round(sum((end - start).total_seconds() for start, end in merged), 6)
    open_ids = [e["id"] for e in data["events"] if e["ended_at"] is None]
    span = "UNKNOWN"
    if intervals and not open_ids:
        span = round((max(end for _, end in intervals) - min(start for start, _ in intervals)).total_seconds(), 6)
    return {"task": data["task"], "events": data["events"], "closed_interval_union_seconds": coverage,
            "recorded_span_seconds": span, "unrecorded_gap_seconds": round(span - coverage, 6) if isinstance(span, (int, float)) else "UNKNOWN",
            "open_event_ids": open_ids, "total_task_wall_seconds": "UNKNOWN", "hidden_reasoning_seconds": "UNKNOWN",
            "tokens": "UNKNOWN", "network_reconnect_seconds": "UNKNOWN",
            "scope": "Only explicit UTC wall-clock intervals; overlapping stages use interval union. No Codex telemetry or automatic task boundaries."}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for action in ("start", "stop", "report"):
        child = commands.add_parser(action)
        child.add_argument("--out", type=Path, required=True)
        if action != "report":
            child.add_argument("--task", required=True)
            child.add_argument("--phase", choices=PHASES, required=True)
            child.add_argument("--reason", default="")
        if action == "stop":
            child.add_argument("--status", choices=STATUSES, required=True)
    args = parser.parse_args(argv)
    try:
        result = report(ROOT, args.out) if args.command == "report" else update(ROOT, args.out, args.task, args.phase,
                     status=args.status if args.command == "stop" else None, reason=args.reason)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (TimingError, OSError) as error:
        print("TIMING_ERROR: " + (str(error) if isinstance(error, TimingError) else type(error).__name__), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
