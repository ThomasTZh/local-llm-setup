# Double-click launcher

`run-local-llm.py` supervises the same router that
[`setup/router/start-router.sh`](../setup/router/start-router.sh) starts. The
installer adds one menu entry. The entry opens a terminal, starts the router,
and closes the terminal when you stop it. No browser opens.

Use it after steps 0 to 3 in [`setup/README.md`](../setup/README.md) have
succeeded. It does not build, download, or install anything else.

## Install

```bash
bash launchers/install-launcher.sh
```

The installer writes `local-llm-router.desktop` to
`${XDG_DATA_HOME:-$HOME/.local/share}/applications` and a small `launch.sh`
wrapper to `${XDG_DATA_HOME:-$HOME/.local/share}/local-llm-router/`. The wrapper
records the absolute path of this checkout and the `AI_HOME`, `AI_HOST`, and
`AI_PORT` values from the install environment. A desktop session does not read
shell profiles, so set those values when you run the installer if your setup
differs from the defaults:

```bash
AI_HOME="$HOME/local-llm-setup" bash launchers/install-launcher.sh
```

Start the entry from the application menu. The generated wrapper names the
interpreter and script explicitly, so the entry does not depend on the desktop
session's `PATH`. Re-run the installer if you move this checkout; the generated
files contain absolute paths.

## Start and stop

| Action | Result |
| --- | --- |
| Open the menu entry | A terminal opens and `setup/router/start-router.sh` starts the router on `AI_HOST:AI_PORT`. |
| Ctrl+C once | SIGTERM the router's process group, wait up to 15 s, SIGKILL survivors, exit 0. The terminal closes. |
| Ctrl+C twice | SIGKILL the process group immediately, exit 0. The terminal closes. |
| Close the terminal | SIGHUP is treated as a clean stop. |
| Open it again | Reports the running instance and exits; no second router starts. |

The router and any model child it loads share one process group. Stopping the
launcher releases both the port and the model's VRAM. Nothing is loaded until a
request names a model, so a launcher start does not use VRAM by itself.

Do not enable `local-ai-router.service` and use this launcher at the same time.
Both bind the same port; the launcher refuses to start if the unit already holds
it.

## Configuration

The supervisor reads these variables from its environment and passes them to
`start-router.sh`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `AI_HOME` | this repository | Install root holding `build/`, `models/`, and `runtime/models.ini` |
| `AI_HOST` | `127.0.0.1` | Router bind address |
| `AI_PORT` | `8080` | Router port |

The installer records the chosen values in the generated wrapper. Without the
installer, run the supervisor from a terminal where the variables are exported:

```bash
AI_HOME="$HOME/local-llm-setup" python3 launchers/run-local-llm.py
```

## Logs and failures

Launcher logs are written to
`~/.local/state/local-llm-router/launcher/logs/` (the ten newest
`launcher-*.log` files are kept). The terminal shows the same lines live.

A startup failure (missing `runtime/models.ini`, missing engine, failed port
bind, occupied port) stays in the terminal until Enter. The launcher never kills
a process it did not start. If the port is busy, find the owner with:

```bash
ss -ltnp 'sport = :8080'
```

The supervisor tracks the process group directly and does not write a state
file, so a stale state file cannot leave an unmanaged router behind.

## Uninstall

```bash
bash launchers/uninstall-launcher.sh
```

This removes the menu entry and the generated wrapper. It leaves the router
installation, the downloaded weights, and the launcher logs in place.

## Verification

There is no separate test suite. The checks used for the release are a shell
syntax check of the installer and uninstaller, a Python byte-compile of the
supervisor, `desktop-file-validate` on the generated entry, and a start/stop run
of the supervisor from a copy of the release tree with `AI_HOME` pointing at the
recorded build and weights. The outcomes are in the root
[`README.md`](../README.md#results).
