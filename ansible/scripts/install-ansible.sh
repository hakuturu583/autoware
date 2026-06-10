#!/usr/bin/env bash
# Bootstrap uv and Ansible so the playbooks under autoware/ansible/ can be run.
#
# Every PyPI-installable tool used by this repo (ansible, the colcon
# toolchain, pre-commit, clang-format, gdown, vcs2l, xmlschema, dco-check,
# mkdocs, ...) is pinned in ../../pyproject.toml as PEP 735 dependency groups
# and resolved with `uv sync`. There is no `pip install` or `uv tool install`
# anywhere in the build path.
#
# This bootstrap step installs the smallest possible slice needed to get
# ansible-playbook on PATH:
#   1. Install the pinned uv release.
#   2. `uv sync --no-default-groups --group ansible` into /opt/uv/venvs/tools.
#   3. Add /opt/uv/venvs/tools/bin to PATH.
#
# After this script, run from the repo root:
#   ansible-galaxy collection install -f -r ansible-galaxy-requirements.yaml
#   ansible-playbook autoware.dev_env.install_dev_env [--skip-tags nvidia ...]

set -euo pipefail

# Keep in sync with ansible/roles/uv/defaults/main.yaml.
UV_VERSION="${UV_VERSION:-0.5.18}"
UV_INSTALL_PREFIX="${UV_INSTALL_PREFIX:-/opt/uv}"
UV_SHARED_VENV="${UV_SHARED_VENV:-${UV_INSTALL_PREFIX}/venvs/tools}"

# Locate the repo root (this script lives at <repo>/ansible/scripts/).
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

if ! command -v sudo >/dev/null 2>&1; then
    apt-get -y update
    apt-get -y install sudo
fi

sudo apt-get -y update
sudo apt-get -y install --no-install-recommends git ca-certificates curl tar

install_uv() {
    local arch tarball
    arch="$(uname -m)"
    case "$arch" in
        x86_64|aarch64) ;;
        *) echo "Unsupported architecture for uv: $arch" >&2; exit 1 ;;
    esac

    tarball="$(mktemp -t uv.XXXXXX.tar.gz)"
    trap 'rm -f "$tarball"' RETURN

    echo "Downloading uv ${UV_VERSION} for ${arch}..."
    curl -fsSL \
        "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${arch}-unknown-linux-gnu.tar.gz" \
        -o "$tarball"

    sudo tar -xzf "$tarball" --strip-components=1 -C /usr/local/bin \
        "uv-${arch}-unknown-linux-gnu/uv" \
        "uv-${arch}-unknown-linux-gnu/uvx"
    sudo chmod 0755 /usr/local/bin/uv /usr/local/bin/uvx
}

current_uv_version() {
    if command -v uv >/dev/null 2>&1; then
        uv --version 2>/dev/null | awk '{print $2}'
    fi
}

if [ "$(current_uv_version)" != "${UV_VERSION}" ]; then
    install_uv
fi

sudo install -d -m 0755 \
    "${UV_INSTALL_PREFIX}" \
    "${UV_INSTALL_PREFIX}/venvs" \
    "${UV_INSTALL_PREFIX}/python" \
    "${UV_INSTALL_PREFIX}/cache"

# Resolve only what we need for ansible — the `uv` role will re-run with the
# full set of groups later. Keeping this fast and matching the reproducible
# resolver path is what justifies not falling back to `pip install ansible`.
sudo --preserve-env=UV_PROJECT_ENVIRONMENT,UV_PYTHON_INSTALL_DIR,UV_CACHE_DIR \
    env \
    UV_PROJECT_ENVIRONMENT="${UV_SHARED_VENV}" \
    UV_PYTHON_INSTALL_DIR="${UV_INSTALL_PREFIX}/python" \
    UV_CACHE_DIR="${UV_INSTALL_PREFIX}/cache" \
    uv sync --no-default-groups --group ansible --project "${REPO_ROOT}"

case ":${PATH}:" in
    *":${UV_SHARED_VENV}/bin:"*) ;;
    *) export PATH="${UV_SHARED_VENV}/bin:${PATH}" ;;
esac

echo "uv installed: $(uv --version)"
echo "ansible installed: $(ansible --version | head -n1)"
echo
echo "Add this to your shell profile if not already present:"
echo "  export PATH=\"${UV_SHARED_VENV}/bin:\$PATH\""
