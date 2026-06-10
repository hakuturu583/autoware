# Role: gdown

`gdown` is pinned in the repo-root `pyproject.toml` `tools` dependency group and installed into `/opt/uv/venvs/tools` by the [`uv` role](../uv/README.md) via `uv sync`. This role exists only so callers can keep depending on the `gdown` tag; it has no install tasks.

## Inputs

None.

## Manual installation

```bash
uv sync --no-default-groups --group tools
```
