# check=skip=InvalidDefaultArgInFrom
ARG ROS_DISTRO

FROM ros:${ROS_DISTRO}-ros-base AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG ROS_DISTRO
ARG USERNAME=aw

RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/99-no-recommends && \
    echo 'APT::Install-Suggests "false";' >> /etc/apt/apt.conf.d/99-no-recommends && \
    echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/99-retries && \
    echo 'Acquire::http::Timeout "30";' >> /etc/apt/apt.conf.d/99-retries && \
    echo 'Acquire::https::Timeout "30";' >> /etc/apt/apt.conf.d/99-retries && \
    printf 'http://azure.archive.ubuntu.com/ubuntu\tpriority:1\nhttp://archive.ubuntu.com/ubuntu\tpriority:2\n' > /etc/apt/ubuntu-mirrors.list && \
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do \
      if [ -f "$f" ]; then \
        sed -E -i 's|http://archive\.ubuntu\.com/ubuntu/?|mirror+file:///etc/apt/ubuntu-mirrors.list|g' "$f"; \
      fi; \
    done

RUN --mount=type=cache,id=apt-cache-${ROS_DISTRO},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${ROS_DISTRO},target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    sudo \
    ca-certificates \
    curl \
    tar \
    bash-completion \
    iproute2 \
    gosu

# Install uv (pinned). Keep UV_VERSION in sync with
# ansible/roles/uv/defaults/main.yaml and ansible/scripts/install-ansible.sh.
ARG UV_VERSION=0.5.18
# hadolint ignore=DL3008
RUN arch="$(uname -m)" && \
    case "$arch" in x86_64|aarch64) ;; *) echo "Unsupported arch: $arch" >&2; exit 1 ;; esac && \
    curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${arch}-unknown-linux-gnu.tar.gz" \
      | tar -xz --strip-components=1 -C /usr/local/bin \
        "uv-${arch}-unknown-linux-gnu/uv" \
        "uv-${arch}-unknown-linux-gnu/uvx" && \
    chmod 0755 /usr/local/bin/uv /usr/local/bin/uvx && \
    install -d -m 0755 /opt/uv /opt/uv/venvs /opt/uv/python /opt/uv/cache

# Remove default ubuntu user (present since 24.04, occupies UID 1000)
RUN userdel -r ubuntu 2>/dev/null || true && \
    useradd -m -s /bin/bash -U ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/90-user-nopasswd && \
    chmod 0440 /etc/sudoers.d/90-user-nopasswd && \
    sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /home/${USERNAME}/.bashrc

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Shared venv produced by `uv sync` against the repo's pyproject.toml. Putting
# it on PATH means ansible / colcon / pre-commit / gdown / vcs2l / mkdocs all
# come from the same uv.lock-pinned environment.
ENV PATH="/opt/uv/venvs/tools/bin:${PATH}"
ENV UV_PYTHON_INSTALL_DIR="/opt/uv/python"
ENV UV_CACHE_DIR="/opt/uv/cache"

# Canonical location of pyproject.toml + uv.lock inside the image. Every later
# `uv sync` invocation (acados role, universe stages, etc.) points at this
# directory so there is one source of truth across stages.
ENV UV_PROJECT_ROOT="/opt/uv-project"

ENV ANSIBLE_COLLECTIONS_PATH="/home/${USERNAME}/.ansible/collections"

# Stage the project metadata into a fixed location. We chown to the user so
# `uv sync --frozen` can write the venv without sudo. uv.lock is required —
# the build fails if it drifts from pyproject.toml.
COPY --chown=${USERNAME}:${USERNAME} pyproject.toml uv.lock ${UV_PROJECT_ROOT}/

# hadolint ignore=DL3003
RUN --mount=type=bind,source=ansible-galaxy-requirements.yaml,target=/tmp/ansible/ansible-galaxy-requirements.yaml \
    --mount=type=bind,source=ansible/galaxy.yml,target=/tmp/ansible/ansible/galaxy.yml \
    --mount=type=bind,source=ansible/roles/rmw_implementation,target=/tmp/ansible/ansible/roles/rmw_implementation \
    --mount=type=bind,source=ansible/playbooks/install_rmw.yaml,target=/tmp/ansible/ansible/playbooks/install_rmw.yaml \
    --mount=type=cache,id=apt-cache-${ROS_DISTRO},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${ROS_DISTRO},target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,id=uv-cache,target=/opt/uv/cache,uid=1000,gid=1000 \
    sudo chown -R ${USERNAME}:${USERNAME} /opt/uv ${UV_PROJECT_ROOT} && \
    UV_PROJECT_ENVIRONMENT=/opt/uv/venvs/tools \
      uv sync --frozen --no-default-groups --group ansible --project "${UV_PROJECT_ROOT}" && \
    cd /tmp/ansible && \
    ansible-galaxy collection install -f -r ansible-galaxy-requirements.yaml && \
    ansible-playbook autoware.dev_env.install_rmw \
      -e rosdistro=${ROS_DISTRO} \
      -e uv_project_root=${UV_PROJECT_ROOT}

COPY docker/files/cyclonedds.xml /home/${USERNAME}/cyclonedds.xml
ENV CYCLONEDDS_URI=file:///home/${USERNAME}/cyclonedds.xml
ENV RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# Entrypoint runs as root so it can adjust UID/GID, then drops to user
USER root
COPY --chmod=755 docker/docker-entrypoint.sh /docker-entrypoint.sh

ENV ROS_DISTRO=${ROS_DISTRO}
ENV USERNAME=${USERNAME}

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/bin/bash"]
