#!/bin/bash -e

# Pin uv. Keep in sync with ansible/roles/uv/defaults/main.yaml and
# ansible/scripts/install-ansible.sh.
UV_VERSION="${UV_VERSION:-0.5.18}"

apt-get update
apt-get -y install sudo curl wget unzip gnupg lsb-release ccache python3-apt apt-utils software-properties-common jq tar ca-certificates
add-apt-repository universe

arch="$(uname -m)"
case "$arch" in
    x86_64|aarch64) ;;
    *) echo "Unsupported architecture for uv: $arch" >&2; exit 1 ;;
esac

tmpdir="$(mktemp -d)"
curl -fsSL \
    "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${arch}-unknown-linux-gnu.tar.gz" \
    | tar -xz --strip-components=1 -C "$tmpdir"
install -m 0755 "$tmpdir/uv" /usr/local/bin/uv
install -m 0755 "$tmpdir/uvx" /usr/local/bin/uvx
rm -rf "$tmpdir"

# Install ansible via uv sync against pyproject.toml (same resolver path as
# the `uv` Ansible role / devcontainer / Dockerfile / install-ansible.sh).
# REPO_ROOT here is the directory containing the autoware checkout; webauto
# mounts it as the runner's CWD.
REPO_ROOT="${WEBAUTO_CI_SOURCE_PATH:-$(pwd)}"
install -d -m 0755 /opt/uv /opt/uv/venvs /opt/uv/python /opt/uv/cache
SHARED_VENV="/opt/uv/venvs/tools"
UV_PROJECT_ENVIRONMENT="${SHARED_VENV}" \
UV_PYTHON_INSTALL_DIR="/opt/uv/python" \
UV_CACHE_DIR="/opt/uv/cache" \
    uv sync --frozen --no-default-groups --group ansible --project "${REPO_ROOT}"
ln -sf "${SHARED_VENV}/bin/ansible" /usr/local/bin/ansible
ln -sf "${SHARED_VENV}/bin/ansible-playbook" /usr/local/bin/ansible-playbook
ln -sf "${SHARED_VENV}/bin/ansible-galaxy" /usr/local/bin/ansible-galaxy

user=autoware
useradd -m "$user" -s /bin/bash
echo "$user:$user" | chpasswd
echo "$user ALL=(ALL) NOPASSWD:ALL" >>/etc/sudoers
gpasswd -a "$user" sudo
