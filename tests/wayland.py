#!/usr/bin/env python3
"""Private native Wayland clipboard regression. Requires Qt compositor dev libs.

All children use a fresh 0700 runtime directory and private socket. No nested
desktop or clipboard bridge is started. Finite providers and independent
process-group watchdogs keep failures bounded. Logs are retained in /tmp.
"""
import json
import os
from pathlib import Path
import re
import resource
import signal
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parent.parent
ROOT = Path(tempfile.mkdtemp(prefix="omarchyform-wayland-"))
BINARY = ROOT / "wayland_clipboard"
SEND = re.compile(r"wl_data_source[#@]\d+\.send\(")
ERROR = re.compile(r"TypeError|ReferenceError|Binding loop|FAIL:")


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (4 * 1024**3,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (20, 20))
    resource.setrlimit(resource.RLIMIT_FSIZE, (8 * 1024**2,) * 2)


def run_case(mode, repo=REPO):
    root = Path(tempfile.mkdtemp(prefix=mode + "-", dir=ROOT))
    root.chmod(0o700)
    (root / "provider.qml").write_text('import QtQuick\nRectangle { width: 100; height: 100 }\n')
    env = dict(os.environ, XDG_RUNTIME_DIR=str(root), WAYLAND_DISPLAY="audit-0",
               QT_QPA_PLATFORM="wayland", QT_QPA_PLATFORMTHEME="", OMARCHYFORM_PRIVATE_WAYLAND="1",
               QT_QUICK_BACKEND="software", QT_WAYLAND_DISABLE_WINDOWDECORATION="1")
    env.pop("DISPLAY", None)
    env.pop("WAYLAND_SOCKET", None)
    env.pop("WAYLAND_DEBUG", None)
    processes, handles, peaks = [], [], {}

    def start(name, args, environment=env):
        log = open(root / (name + ".log"), "wb")
        handles.append(log)
        p = subprocess.Popen(args, env=environment, stdout=log, stderr=log,
                             start_new_session=True, preexec_fn=limits)
        processes.append((name, p))
        return p

    def log(name):
        return (root / (name + ".log")).read_text(errors="replace")

    def session_processes():
        sessions = {p.pid for _, p in processes}
        for entry in Path("/proc").glob("[0-9]*/stat"):
            try:
                fields = entry.read_text().rsplit(")", 1)[1].split()
                if int(fields[3]) in sessions:
                    yield int(fields[3]), int(fields[2]), int(fields[21]) * os.sysconf("SC_PAGE_SIZE")
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                pass

    def watchdog():
        # timeout creates another process group, but retains this private
        # session. Account for every group in the tree, not only the launcher.
        rss = {p.pid: 0 for _, p in processes}
        for session, _, memory in session_processes():
            rss[session] += memory
        for name, p in processes:
            peaks[name] = max(peaks.get(name, 0), rss[p.pid])
            if rss[p.pid] > 512 * 1024**2:
                raise RuntimeError("process-tree RSS watchdog exceeded")
        if time.monotonic() - started > 18:
            raise RuntimeError("wall watchdog exceeded")

    started = time.monotonic()
    verdict = "FAIL"
    reason = ""
    try:
        server = start("server", [str(BINARY), "server"], dict(env, QT_QPA_PLATFORM="offscreen"))
        while not (root / "audit-0").exists():
            watchdog()
            if server.poll() is not None:
                raise RuntimeError("server startup failed")
            time.sleep(.02)
        provider_mode = mode if mode in ("large", "exact") else "finite"
        provider = start("provider", [str(BINARY), "provider", str(root / "provider.qml"), provider_mode],
                         dict(env, WAYLAND_DEBUG="client"))
        while "OFFER" not in log("provider"):
            watchdog()
            if provider.poll() is not None:
                raise RuntimeError("provider startup failed")
            time.sleep(.02)
        if mode in ("slow", "stall"):
            os.kill(provider.pid, signal.SIGSTOP)
        consumer_started = time.monotonic()
        if mode == "finite":
            consumer = start("consumer", [str(BINARY), "consumer", str(repo / "tests/qt/clipboard_scene.qml")])
        else:
            # cliptext stages the clipboard in a folder of the caller's own.
            staging = root / "staging"
            staging.mkdir(mode=0o700)
            consumer = start("consumer", ["bash", str(repo / "BoardFiles.sh"), "cliptext", str(staging)])
        resumed = False
        while True:
            watchdog()
            if mode == "slow" and not resumed and time.monotonic() - consumer_started >= 1:
                os.kill(provider.pid, signal.SIGCONT)
                resumed = True
            if mode == "finite" and SEND.search(log("provider")) and "POSITIVE_CONTROL" not in log("consumer"):
                raise RuntimeError("unsolicited native receive request")
            if consumer.poll() is not None:
                break
            if server.poll() is not None or provider.poll() is not None:
                raise RuntimeError("infrastructure exited")
            time.sleep(.02)
        output = (root / "consumer.log").read_bytes()
        elapsed = time.monotonic() - consumer_started
        expected = 5 if mode == "large" else 4 if mode == "stall" else 0
        if consumer.returncode != expected:
            raise RuntimeError(f"consumer exit {consumer.returncode}, expected {expected}")
        if ERROR.search(log("consumer")):
            raise RuntimeError("QML diagnostic failure")
        if mode == "finite":
            if not SEND.search(log("provider")) or "POSITIVE_BYTES 32" not in log("consumer"):
                raise RuntimeError("positive control failed")
        elif mode in ("large", "stall"):
            if output:
                raise RuntimeError("rejected paste returned partial output or a diagnostic")
            if mode == "stall" and not 2.5 <= elapsed <= 4.5:
                raise RuntimeError("timeout did not match the helper deadline")
        elif output != b"x" * (1048576 if mode == "exact" else 32):
            raise RuntimeError("accepted paste content differs")
        verdict = "PASS"
    except Exception as error:
        reason = str(error)
    finally:
        groups = {group for _, group, _ in session_processes()}
        groups.update(p.pid for _, p in processes)
        for group in groups:
            try:
                os.killpg(group, signal.SIGKILL)
            except ProcessLookupError:
                pass
        for _, p in reversed(processes):
            p.wait()
        for handle in handles:
            handle.close()
        result = dict(case=mode, verdict=verdict, reason=reason,
                      seconds=round(time.monotonic() - started, 2), peak_process_tree_rss_bytes=peaks,
                      logs=str(root), budgets=dict(wall_seconds=18, rss_per_tree=512 * 1024**2,
                      address_space_per_process=4 * 1024**3, cpu_seconds_per_process=20))
        (root / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result), flush=True)
    return verdict == "PASS"


try:
    flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "Qt6Quick", "Qt6Gui", "Qt6WaylandCompositor"], text=True).split()
    subprocess.run(["g++", "-std=c++17", "-fPIC", str(REPO / "tests/qt/wayland_clipboard.cpp"),
                    "-o", str(BINARY), *flags], check=True, timeout=120)
    results = [run_case(mode) for mode in ("finite", "normal", "exact", "large", "slow", "stall")]
    sys.exit(0 if all(results) else 1)
except Exception as error:
    print(f"FAIL: {error}; logs: {ROOT}", file=sys.stderr)
    sys.exit(1)
