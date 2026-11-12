#!/usr/bin/env python3
"""Supervisor for the Local LLM router double-click launcher.

Starts setup/router/start-router.sh, waits until /health answers, and keeps
running. The router is an API-only service; no browser is opened.

The service reads AI_HOME (default: this repository), AI_HOST (default
127.0.0.1), and AI_PORT (default 8080) from the environment.

Ctrl+C once:  stop every service cleanly (SIGTERM, wait, SIGKILL if needed),
              then exit so the terminal window closes.
Ctrl+C twice: SIGKILL every service immediately, then exit.
Closing the terminal window is treated as a clean stop.

Requires Python 3.9+ and POSIX (Linux/macOS). Standard library only.
"""

from __future__ import annotations

import argparse
import fcntl
import os
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple


# ===========================================================================
# CONFIG: values for the local llama.cpp catalogue router.
# ===========================================================================

# Stable, filesystem-safe name. Used for the log/lock directory.
PRODUCT_SLUG = "local-llm-router"

# Shown in messages.
PRODUCT_NAME = "Local LLM router"

# Launcher lives in launchers/ under the project root, two levels up.
PROJECT_ROOT = Path(__file__).resolve().parent.parent


def _env_port() -> int:
    raw = os.environ.get("AI_PORT") or "8080"
    try:
        port = int(raw)
    except ValueError:
        raise SystemExit(f"AI_PORT must be an integer, got {raw!r}")
    if not 1 <= port <= 65535:
        raise SystemExit(f"AI_PORT must be between 1 and 65535, got {port}")
    return port


AI_HOME = Path(os.environ.get("AI_HOME") or PROJECT_ROOT).expanduser()
AI_HOST = os.environ.get("AI_HOST") or "127.0.0.1"
AI_PORT = _env_port()
PROBE_HOST = "127.0.0.1" if AI_HOST in ("0.0.0.0", "::", "") else AI_HOST

# llama.cpp has no web UI; this catalogue URL is informational only.
FRONTEND_URL = f"http://{PROBE_HOST}:{AI_PORT}/v1/models"

# The router is an API-only service; do not open a browser window.
OPEN_BROWSER = False


@dataclass(frozen=True)
class ServiceConfig:
    """One process group the supervisor starts and stops."""

    name: str
    command: Sequence[str]
    cwd: Path
    # Readiness probes: http(s) URL returning < 500, or "tcp://host:port".
    readiness: Sequence[str] = ()
    # Extra environment variables for this service.
    env: Dict[str, str] = field(default_factory=dict)


SERVICES: Sequence[ServiceConfig] = (
    ServiceConfig(
        name="llama.cpp router",
        command=(
            "/bin/bash",
            str(PROJECT_ROOT / "setup" / "router" / "start-router.sh"),
        ),
        cwd=PROJECT_ROOT,
        readiness=(f"http://{PROBE_HOST}:{AI_PORT}/health",),
        env={
            "AI_HOME": str(AI_HOME),
            "AI_HOST": AI_HOST,
            "AI_PORT": str(AI_PORT),
        },
    ),
)

# The router binds its port without preloading a model.
STARTUP_TIMEOUT = 180.0
# A loaded model needs a few seconds to release VRAM before the router exits.
GRACEFUL_TIMEOUT = 15.0
# Seconds to wait after SIGKILL before giving up.
FORCE_TIMEOUT = 3.0
# Keep a startup/runtime failure visible when launched by double-click.
HOLD_ON_FAILURE = True
# Keep this many log files; older ones are deleted.
LOG_FILES_TO_KEEP = 10

# ===========================================================================


STATE_HOME = Path(
    os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state"))
)
STATE_DIR = STATE_HOME / PRODUCT_SLUG / "launcher"
LOG_DIR = STATE_DIR / "logs"
LOCK_FILE = STATE_DIR / "launcher.lock"

_PRINT_LOCK = threading.RLock()


class StartupError(RuntimeError):
    """A precondition, readiness, or early-exit failure during startup."""


def emit(message: str) -> None:
    """Print a launcher message without crashing after the terminal closes."""
    with _PRINT_LOCK:
        try:
            print(message, flush=True)
        except (BrokenPipeError, OSError):
            pass


class Logger:
    """Write prefixed service output to the terminal and the log file."""

    def __init__(self, path: Path) -> None:
        self._file = open(path, "a", encoding="utf-8", errors="replace", buffering=1)
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
        self._lock = threading.RLock()

    def line(self, label: str, message: str) -> None:
        message = message.rstrip("\r\n")
        text = f"[{label}] {message}" if label else message
        stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with self._lock:
            with _PRINT_LOCK:
                try:
                    print(text, flush=True)
                except (BrokenPipeError, OSError):
                    pass
            try:
                self._file.write(f"{stamp} {text}\n")
            except (OSError, ValueError):
                pass

    def info(self, message: str) -> None:
        self.line("launcher", message)

    def stream(self, name: str, chunk: str) -> None:
        self.line(name, chunk)

    def close(self) -> None:
        with self._lock:
            try:
                self._file.close()
            except OSError:
                pass


def prune_logs(keep: int) -> None:
    try:
        logs = sorted(LOG_DIR.glob("launcher-*.log"))
    except OSError:
        return
    for old in logs[:-keep] if keep > 0 else logs:
        try:
            old.unlink()
        except OSError:
            pass


def tcp_target(url: str) -> Optional[Tuple[str, int]]:
    """Extract (host, port) from an HTTP(S) or tcp:// readiness URL."""
    if url.startswith("tcp://"):
        rest = url[len("tcp://"):].rstrip("/")
    else:
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme not in ("http", "https"):
            return None
        rest = parsed.netloc
    if "@" in rest:
        rest = rest.rsplit("@", 1)[1]
    host, sep, port_text = rest.rpartition(":")
    if not sep:
        return None
    try:
        port = int(port_text)
    except ValueError:
        return None
    host = host.strip("[]") or "127.0.0.1"
    if host in ("0.0.0.0", "::"):
        host = "127.0.0.1"
    return host, port


def port_open(host: str, port: int, timeout: float = 0.3) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def endpoint_ready(url: str, timeout: float = 1.0) -> bool:
    if url.startswith("tcp://"):
        target = tcp_target(url)
        return target is not None and port_open(*target, timeout=timeout)
    try:
        request = urllib.request.Request(
            url, headers={"User-Agent": "product-launcher-readiness"}
        )
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status < 500
    except urllib.error.HTTPError as exc:
        # A 4xx still proves the server is listening.
        return exc.code < 500
    except (urllib.error.URLError, ValueError, OSError):
        return False


def preflight(services: Sequence[ServiceConfig]) -> None:
    problems: List[str] = []
    checked_ports = set()
    for service in services:
        if not service.cwd.is_dir():
            problems.append(f"{service.name}: working directory does not exist: {service.cwd}")
            continue

        executable = str(service.command[0])
        environment = os.environ.copy()
        environment.update(service.env)
        if os.sep in executable or (os.altsep and os.altsep in executable):
            path = Path(executable)
            if not path.is_absolute():
                path = service.cwd / path
            if not path.exists():
                problems.append(f"{service.name}: executable not found: {path}")
        elif shutil.which(executable, path=environment.get("PATH")) is None:
            problems.append(
                f"{service.name}: command {executable!r} not found on PATH. "
                "Desktop-launched processes do not read your shell profile; "
                "use an absolute path in ServiceConfig.command."
            )

        for url in service.readiness:
            target = tcp_target(url)
            if target is None or target in checked_ports:
                continue
            checked_ports.add(target)
            host, port = target
            if port_open(host, port):
                problems.append(
                    f"port {port} on {host} is already in use. "
                    "Stop the other process or change the configured port."
                )

    if problems:
        raise StartupError("Preflight failed:\n  - " + "\n  - ".join(problems))


class RunningService:
    """One supervised child process group."""

    def __init__(self, config: ServiceConfig, logger: Logger) -> None:
        self.config = config
        self.logger = logger
        self.proc: Optional[subprocess.Popen] = None
        self.pgid: Optional[int] = None
        self._reader: Optional[threading.Thread] = None

    def start(self) -> None:
        environment = os.environ.copy()
        environment.update(self.config.env)
        environment.setdefault("PYTHONUNBUFFERED", "1")
        command_text = " ".join(shlex.quote(str(part)) for part in self.config.command)
        self.logger.info(f"{self.config.name}: starting {command_text} (cwd {self.config.cwd})")
        self.proc = subprocess.Popen(
            [str(part) for part in self.config.command],
            cwd=str(self.config.cwd),
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            start_new_session=True,
        )
        self.pgid = os.getpgid(self.proc.pid)
        self.logger.info(
            f"{self.config.name}: pid {self.proc.pid}, process group {self.pgid}"
        )
        self._reader = threading.Thread(
            target=self._pump, name=f"{self.config.name}-log", daemon=True
        )
        self._reader.start()

    def _pump(self) -> None:
        if self.proc is None or self.proc.stdout is None:
            return
        try:
            for chunk in self.proc.stdout:
                self.logger.stream(self.config.name, chunk)
        except (OSError, ValueError):
            pass
        finally:
            try:
                self.proc.stdout.close()
            except OSError:
                pass

    def exit_code(self) -> Optional[int]:
        if self.proc is None:
            return None
        return self.proc.poll()

    def group_alive(self) -> bool:
        if self.pgid is None:
            return False
        try:
            os.killpg(self.pgid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return True

    def alive(self) -> bool:
        if self.proc is None:
            return False
        if self.proc.poll() is None:
            return True
        return self.group_alive()

    def terminate(self) -> None:
        if self.pgid is None:
            return
        try:
            os.killpg(self.pgid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    def kill(self) -> None:
        if self.pgid is None:
            return
        try:
            os.killpg(self.pgid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    def reap(self, timeout: float) -> None:
        if self.proc is None:
            return
        try:
            self.proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            pass


class InstanceLock:
    """Advisory lock so a second double-click cannot start a second copy."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self._file = None

    def acquire(self) -> bool:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._file = open(self.path, "a+")
        try:
            fcntl.flock(self._file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self._file.close()
            self._file = None
            return False
        self._file.seek(0)
        self._file.truncate()
        self._file.write(str(os.getpid()))
        self._file.flush()
        return True

    def release(self) -> None:
        if self._file is None:
            return
        try:
            fcntl.flock(self._file.fileno(), fcntl.LOCK_UN)
        except OSError:
            pass
        try:
            self._file.close()
        except OSError:
            pass
        self._file = None


def wait_for_ready(
    running: Sequence[RunningService],
    stop_event: threading.Event,
    force_event: threading.Event,
    timeout: float,
) -> None:
    pending: Dict[str, List[str]] = {
        service.config.name: list(service.config.readiness)
        for service in running
        if service.config.readiness
    }
    deadline = time.monotonic() + timeout
    next_report = 0.0

    while pending:
        if force_event.is_set():
            raise StartupError("force stop requested during startup")
        if stop_event.is_set():
            raise StartupError("stop requested during startup")

        for service in running:
            code = service.exit_code()
            if code is not None:
                raise StartupError(
                    f"{service.config.name} exited during startup with code {code}"
                )

        for name in list(pending):
            remaining = [url for url in pending[name] if not endpoint_ready(url)]
            if remaining:
                pending[name] = remaining
            else:
                del pending[name]
                emit(f"  ready: {name}")

        if not pending:
            break
        now = time.monotonic()
        if now > deadline:
            detail = "; ".join(
                f"{name}: {', '.join(urls)}" for name, urls in pending.items()
            )
            raise StartupError(
                f"timed out after {timeout:.0f}s waiting for {detail}"
            )
        if now >= next_report:
            emit(f"Waiting for {', '.join(pending)} ...")
            next_report = now + 5.0
        time.sleep(0.4)


def monitor(
    running: Sequence[RunningService],
    stop_event: threading.Event,
    force_event: threading.Event,
) -> Tuple[Optional[str], int]:
    while not stop_event.is_set():
        if force_event.is_set():
            break
        for service in running:
            code = service.exit_code()
            if code is not None and not service.group_alive():
                return (
                    f"{service.config.name} exited unexpectedly with code {code}",
                    1,
                )
        time.sleep(0.25)
    return None, 0


def graceful_shutdown(
    running: Sequence[RunningService], force_event: threading.Event
) -> None:
    if not running:
        return

    emit("Stopping services ...")
    for service in running:
        service.terminate()

    deadline = time.monotonic() + GRACEFUL_TIMEOUT
    while any(service.alive() for service in running):
        if force_event.is_set():
            break
        if time.monotonic() >= deadline:
            break
        time.sleep(0.1)

    if any(service.alive() for service in running):
        emit("Services did not stop in time; force-killing them ...")
        for service in running:
            service.kill()
        kill_deadline = time.monotonic() + FORCE_TIMEOUT
        while any(service.alive() for service in running):
            if time.monotonic() >= kill_deadline:
                break
            time.sleep(0.1)

    for service in running:
        service.reap(2.0)

    survivors = [
        f"{service.config.name} (pgid {service.pgid})"
        for service in running
        if service.alive()
    ]
    if survivors:
        emit(
            "WARNING: these process groups are still alive: "
            + ", ".join(survivors)
            + ". Check them with: ps -o pid,pgid,cmd -g PGID"
        )
    else:
        emit("All services stopped.")


def install_signal_handlers(
    stop_event: threading.Event, force_event: threading.Event
) -> None:
    count = {"value": 0}

    def handler(signum, _frame) -> None:
        if signum == signal.SIGINT:
            count["value"] += 1
            if count["value"] == 1:
                emit("\nStopping ... press Ctrl+C again to force stop.")
                stop_event.set()
            else:
                emit("\nForcing stop ...")
                force_event.set()
                stop_event.set()
        else:
            emit(f"\nReceived {signal.Signals(signum).name}; stopping ...")
            stop_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, handler)


def open_browser(url: str) -> None:
    try:
        if sys.platform == "darwin":
            command = ["open", url]
        else:
            command = ["xdg-open", url]
        subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        emit(f"Could not open a browser automatically. Open: {url}")


def print_running_banner(running: Sequence[RunningService]) -> None:
    lines = ["", "=" * 68, f" {PRODUCT_NAME} is running"]
    lines.append(f" Catalogue: {FRONTEND_URL}")
    for service in running:
        if service.config.readiness:
            lines.append(
                f" {service.config.name}: {', '.join(service.config.readiness)}"
            )
    lines.extend(
        [
            " Ctrl+C once  stop cleanly and close this terminal",
            " Ctrl+C twice force stop",
            "=" * 68,
            "",
        ]
    )
    emit("\n".join(lines))


def hold_on_failure(args: argparse.Namespace) -> None:
    if args.no_hold or not HOLD_ON_FAILURE:
        return
    try:
        if sys.stdin.isatty():
            input("Press Enter to close this window ...")
    except (EOFError, KeyboardInterrupt, OSError):
        pass


def parse_args(argv: Optional[Sequence[str]]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=f"Double-click launcher supervisor for {PRODUCT_NAME}."
    )
    parser.add_argument(
        "--no-browser",
        action="store_true",
        help="do not open the catalogue URL in a browser",
    )
    parser.add_argument(
        "--no-hold",
        action="store_true",
        help="close the window even when startup fails",
    )
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    if os.name == "nt":
        emit("This launcher supports Linux and macOS only.")
        return 1

    args = parse_args(argv)
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
        LOG_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    except OSError as exc:
        emit(f"ERROR: cannot create launcher state directory {STATE_DIR}: {exc}")
        return 1

    lock = InstanceLock(LOCK_FILE)
    try:
        acquired = lock.acquire()
    except OSError as exc:
        emit(f"ERROR: cannot lock launcher state: {exc}")
        return 1
    if not acquired:
        emit(f"{PRODUCT_NAME} launcher is already running.")
        if OPEN_BROWSER and not args.no_browser and endpoint_ready(FRONTEND_URL, timeout=1.0):
            open_browser(FRONTEND_URL)
        return 0

    logger: Optional[Logger] = None
    running: List[RunningService] = []
    error: Optional[str] = None
    exit_code = 0

    stop_event = threading.Event()
    force_event = threading.Event()
    install_signal_handlers(stop_event, force_event)

    try:
        prune_logs(LOG_FILES_TO_KEEP)
        log_path = LOG_DIR / f"launcher-{datetime.now():%Y%m%d-%H%M%S}.log"
        logger = Logger(log_path)

        logger.info(f"{PRODUCT_NAME} launcher")
        logger.info(f"Log file: {log_path}")
        preflight(SERVICES)

        for config in SERVICES:
            service = RunningService(config, logger)
            service.start()
            running.append(service)

        wait_for_ready(running, stop_event, force_event, STARTUP_TIMEOUT)

        if OPEN_BROWSER and not args.no_browser:
            open_browser(FRONTEND_URL)
        print_running_banner(running)

        error, exit_code = monitor(running, stop_event, force_event)

    except StartupError as exc:
        if stop_event.is_set():
            exit_code = 0
        else:
            error = str(exc)
            exit_code = 1
    except Exception as exc:  # keep unexpected failures readable
        error = f"unexpected launcher error: {exc!r}"
        exit_code = 1
    finally:
        graceful_shutdown(running, force_event)
        if error:
            emit(f"\nERROR: {error}")
            if logger is not None:
                logger.info(f"ERROR: {error}")
            hold_on_failure(args)
        else:
            emit("Launcher stopped. Closing this window.")
            if logger is not None:
                logger.info("Launcher stopped.")
        if logger is not None:
            logger.close()
        lock.release()

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
