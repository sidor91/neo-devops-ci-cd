#!/usr/bin/env bash
set -Eeuo pipefail

step='Distribution detection'
trap 'status=$?; printf "Error [%s]: command failed on line %s (exit %s).\n" "$step" "$LINENO" "$status" >&2; exit "$status"' ERR

fail() {
    printf 'Error [%s]: %s\n' "$step" "$1" >&2
    exit 1
}

[[ -r /etc/os-release ]] || fail 'Cannot read /etc/os-release.'
# shellcheck disable=SC1091
source /etc/os-release
case "${ID:-}" in
    ubuntu) compose_package=docker-compose-v2 ;;
    debian) compose_package=docker-compose ;;
    *) fail "Unsupported distribution: ${ID:-unknown}. Use Ubuntu or Debian." ;;
esac

apt_updated=0
install_packages() {
    local -a as_root=()
    if (( EUID != 0 )); then
        command -v sudo >/dev/null || fail 'sudo is required to install system packages.'
        as_root=(sudo)
    fi

    if (( ! apt_updated )); then
        "${as_root[@]}" apt-get update
        apt_updated=1
    fi
    "${as_root[@]}" apt-get install -y --no-install-recommends --no-remove "$@"
}

has_docker_engine() {
    # Debian installs dockerd in /usr/sbin, which may be outside the user's PATH.
    dockerd --version >/dev/null 2>&1 || /usr/sbin/dockerd --version >/dev/null 2>&1
}

has_docker_cli() {
    docker --version >/dev/null 2>&1
}

compose_version() {
    docker compose version 2>/dev/null || docker-compose --version 2>/dev/null
}

python_at_least_39() {
    "$1" -c 'import sys; raise SystemExit(sys.version_info < (3, 9))' >/dev/null 2>&1
}

find_python() {
    local candidate interpreter
    for candidate in python3 python /usr/bin/python3; do
        interpreter=$(type -P "$candidate") || continue
        if python_at_least_39 "$interpreter"; then
            printf '%s\n' "$interpreter"
            return
        fi
    done
    return 1
}

has_usable_venv() {
    "$venv_python" -c 'import sys; raise SystemExit(sys.prefix == sys.base_prefix or sys.version_info < (3, 9))' >/dev/null 2>&1
}

step='Docker Engine and CLI'
if has_docker_engine && has_docker_cli; then
    printf '[skip] %s\n' "$step"
else
    if [[ $ID == ubuntu ]]; then
        install_packages docker.io
    else
        docker_packages=()
        if ! has_docker_engine; then
            docker_packages+=(docker.io)
        fi
        if ! has_docker_cli; then
            docker_packages+=(docker-cli)
        fi
        install_packages "${docker_packages[@]}"
    fi
    (has_docker_engine && has_docker_cli) || fail 'Docker Engine or CLI is unavailable after installation.'
    printf '[installed] %s\n' "$step"
fi

step='Docker Compose'
if version=$(compose_version); then
    printf '[skip] %s (%s)\n' "$step" "$version"
else
    install_packages "$compose_package"
    version=$(compose_version) || fail 'Neither docker compose nor docker-compose is available after installation.'
    printf '[installed] %s (%s)\n' "$step" "$version"
fi

step='Python'
if python_bin=$(find_python); then
    printf '[skip] %s (%s)\n' "$step" "$("$python_bin" --version)"
else
    install_packages python3
    python_bin=$(find_python) || fail 'Python 3.9 or newer is unavailable after installation.'
    printf '[installed] %s (%s)\n' "$step" "$("$python_bin" --version)"
fi

step='Django'
[[ -n ${HOME:-} ]] || fail 'HOME is required to locate the virtual environment.'
venv_dir="$HOME/.venvs/goit-dev-tools"
venv_python="$venv_dir/bin/python"

if version=$("$python_bin" -m django --version 2>/dev/null); then
    django_python=$python_bin
    printf '[skip] %s (%s)\n' "$step" "$version"
elif has_usable_venv && version=$("$venv_python" -m django --version 2>/dev/null); then
    django_python=$venv_python
    printf '[skip] %s (%s)\n' "$step" "$version"
else
    # Use an isolated environment on distributions that manage system Python.
    # https://packaging.python.org/en/latest/specifications/externally-managed-environments/
    if ! has_usable_venv; then
        "$python_bin" -m venv --without-pip "$venv_dir"
        has_usable_venv || fail "No usable Python 3.9+ virtual environment at $venv_dir."
    fi
    if ! "$venv_python" -m pip --version >/dev/null 2>&1; then
        if ! "$venv_python" -c 'import ensurepip' >/dev/null 2>&1; then
            install_packages python3-venv
        fi
        "$venv_python" -m ensurepip
    fi
    "$venv_python" -m pip --require-virtualenv install Django
    django_python=$venv_python
    version=$("$django_python" -m django --version)
    printf '[installed] %s (%s)\n' "$step" "$version"
fi

printf 'Verify Django: %q -m django --version\n' "$django_python"
