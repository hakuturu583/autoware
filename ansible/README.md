# Ansible Collection - autoware.dev_env

This collection contains the playbooks to set up the development environment for Autoware.

## Set up a development environment

### Ansible installation

Every PyPI-installable tool used by this repo (ansible, the colcon toolchain, pre-commit, clang-format, gdown, vcs2l, xmlschema, dco-check, mkdocs) is pinned in the repo-root `pyproject.toml` as PEP 735 dependency groups and resolved with `uv sync`. The bootstrap script installs a pinned [uv](https://github.com/astral-sh/uv) and then runs `uv sync --no-default-groups --group ansible` so `ansible-playbook` lands on PATH; later the [`uv` role](./roles/uv/README.md) re-syncs with the full set of groups.

```bash
bash ansible/scripts/install-ansible.sh
```

By hand:

```bash
# Install uv (pinned)
UV_VERSION=0.5.18
arch="$(uname -m)"
curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${arch}-unknown-linux-gnu.tar.gz" \
  | sudo tar -xz --strip-components=1 -C /usr/local/bin \
    "uv-${arch}-unknown-linux-gnu/uv" "uv-${arch}-unknown-linux-gnu/uvx"
sudo install -d -m 0755 /opt/uv /opt/uv/venvs /opt/uv/python /opt/uv/cache

# Resolve ansible from pyproject.toml's `ansible` group
UV_PROJECT_ENVIRONMENT=/opt/uv/venvs/tools \
UV_PYTHON_INSTALL_DIR=/opt/uv/python \
UV_CACHE_DIR=/opt/uv/cache \
sudo --preserve-env=UV_PROJECT_ENVIRONMENT,UV_PYTHON_INSTALL_DIR,UV_CACHE_DIR \
  uv sync --no-default-groups --group ansible --project "$(pwd)"

export PATH="/opt/uv/venvs/tools/bin:$PATH"
```

### Install ansible collections

This step should be repeated when a new playbook is added.

```bash
cd ~/autoware # The root directory of the cloned repository
ansible-galaxy collection install -f -r "ansible-galaxy-requirements.yaml"
```
