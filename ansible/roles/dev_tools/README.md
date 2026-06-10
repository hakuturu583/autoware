# dev_tools

Installs optional non-PyPI development tools for Autoware. PyPI dev tools (`pre-commit`, `clang-format`) live in the repo-root `pyproject.toml` `dev-tools` group and are materialized into `/opt/uv/venvs/tools` by the [`uv` role](../uv/README.md) via `uv sync` — this role no longer touches them.

## Tools

- Git LFS (apt)
- Go (apt)
- PlotJuggler (apt, `ros-${rosdistro}-plotjuggler`)
- pre-commit, clang-format (uv-managed, see `pyproject.toml [dependency-groups] dev-tools`)

## Inputs

| Name      | Required | Description           |
| --------- | -------- | --------------------- |
| rosdistro | true     | The ROS distribution. |

## Manual installation

```bash
# Choose your ROS distribution
rosdistro=humble  # or jazzy

sudo apt-get update
sudo apt install -y golang ros-${rosdistro}-plotjuggler-ros git-lfs

git lfs install

# pre-commit and clang-format come via uv sync (see ../uv/README.md).
uv sync --no-default-groups --group dev-tools
```
