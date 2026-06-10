# Setup uv

Installs [uv](https://github.com/astral-sh/uv) and **runs `uv sync` against the repo-root `pyproject.toml`** so that every PyPI-installable build tool used by this repo (ansible, the colcon toolchain, pre-commit, clang-format, gdown, vcs2l, xmlschema, dco-check, mkdocs, ...) lands in one resolver-pinned environment.

## What it does

1. Downloads the pinned uv release tarball (`uv_version` in `defaults/main.yaml`) for the host architecture (`x86_64` / `aarch64`) and installs `uv` + `uvx` to `/usr/local/bin`.
2. Creates a shared install prefix at `/opt/uv` with `venvs/`, `python/`, and `cache/` subdirectories.
3. Runs `uv sync --no-default-groups --group ansible --group colcon --group dev-tools --group tools` against `pyproject.toml` (located via `uv_project_root`, default = repo root), materializing `/opt/uv/venvs/tools`.
4. Exports `UV_PYTHON_INSTALL_DIR`, `UV_CACHE_DIR`, and prepends `/opt/uv/venvs/tools/bin` to `PATH` in `~/.bashrc` and `/etc/skel/.bashrc`.

That's it — no `uv tool install`, no `pip install`. Other roles (`acados`, `ros2_dev_tools`, `dev_tools`, `gdown`) **don't install anything Python-flavored themselves**; they just assume the shared venv (or, for acados, a separate `uv sync --group acados` venv) is already populated.

## Why pin uv

The whole point of routing PyPI installs through uv is to make builds reproducible. Pinning uv itself is what closes the loop — otherwise `uv sync` resolves against whatever resolver shipped this week.

## Inputs

| Variable                | Default                            | Purpose                                                  |
| ----------------------- | ---------------------------------- | -------------------------------------------------------- |
| `uv_version`            | `0.5.18`                           | Pinned uv release                                        |
| `uv_install_prefix`     | `/opt/uv`                          | Root of the shared uv tree                               |
| `uv_shared_venv`        | `/opt/uv/venvs/tools`              | Destination of the shared `uv sync`                      |
| `uv_shared_groups`      | `[ansible, colcon, dev-tools, tools]` | Dependency groups synced into the shared venv         |
| `uv_project_root`       | (auto: repo root)                  | Directory containing `pyproject.toml` + `uv.lock`        |

## Installation

```bash
ansible-playbook autoware.dev_env.install_dev_env --tags uv --ask-become-pass
```

After this, `colcon`, `ansible`, `pre-commit`, `gdown`, `vcs import`, `dco-check`, etc. all resolve from `/opt/uv/venvs/tools/bin`.

## Requirements

- `tar`, `curl`
- Network access to `github.com/astral-sh/uv` releases and to PyPI / GitHub (for `colcon-uv`'s git source)
