# ros2_dev_tools

Installs the apt-side ROS 2 development tools (lint plugins, `bloom`, `rosdep`, `vcs2l` from the distro). The Python-flavored colcon toolchain is **not** installed here — it lives in the repo-root `pyproject.toml` `colcon` group and is materialized into `/opt/uv/venvs/tools` by the [`uv` role](../uv/README.md) via `uv sync`.

## Why split it this way

`colcon-common-extensions`, `colcon-mixin`, and the tier4 `colcon-uv` plugin must share a single Python environment so colcon's entry points can discover all three. Routing them through `uv sync --group colcon` is what makes that guarantee — they all land in `/opt/uv/venvs/tools` and are resolved together against `uv.lock`.

## Inputs

None — all Python pins live in `pyproject.toml`.

## Manual installation

```bash
# OS deps (lint plugins, build essentials, vcs, rosdep)
sudo apt update && sudo apt install -y \
  python3-flake8-docstrings python3-pytest-cov \
  python3-flake8-blind-except python3-flake8-builtins \
  python3-flake8-class-newline python3-flake8-comprehensions \
  python3-flake8-deprecated python3-flake8-import-order \
  python3-flake8-quotes python3-pytest-repeat \
  python3-pytest-rerunfailures \
  ros-build-essential python3-bloom python3-rosdep python3-vcs2l wget

# colcon + plugins from PyPI via uv sync
# (the `uv` role already does this for you; this is the manual equivalent)
uv sync --no-default-groups --group colcon

# Initialize rosdep
sudo rosdep init
rosdep update
```
