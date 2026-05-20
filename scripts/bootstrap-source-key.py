#!/usr/bin/env python3
"""Bootstrap SOURCE_SSH_KEY onto the source server using SOURCE_PASSWORD.

This is intentionally separate from the Bash migration scripts. Password auth is
acceptable for one-time key installation, but the migration phases should use
key-based SSH so they can stream data and fail predictably.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import sys

import paramiko


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]


def load_env() -> dict[str, str]:
    env_file = os.environ.get("ENV_FILE")
    if env_file:
        path = pathlib.Path(env_file)
    elif (REPO_ROOT / ".env").exists():
        path = REPO_ROOT / ".env"
    else:
        path = REPO_ROOT / ".env.develop"

    values = dict(os.environ)
    if path.exists():
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")

    return values


def expand_local_path(value: str) -> pathlib.Path:
    expanded = os.path.expanduser(value)
    if len(expanded) >= 3 and expanded[1:3] == ":\\":
        return pathlib.Path(expanded)
    if expanded.startswith("/c/"):
        return pathlib.Path("C:/" + expanded[3:])
    if expanded.startswith("/mnt/c/"):
        return pathlib.Path("C:/" + expanded[7:])
    return pathlib.Path(expanded)


def public_key_path(private_key_path: pathlib.Path) -> pathlib.Path:
    return pathlib.Path(str(private_key_path) + ".pub")


def run(client: paramiko.SSHClient, command: str) -> tuple[int, str, str]:
    stdin, stdout, stderr = client.exec_command(command)
    out = stdout.read().decode("utf-8", errors="replace")
    err = stderr.read().decode("utf-8", errors="replace")
    code = stdout.channel.recv_exit_status()
    return code, out, err


def shell_single_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--execute", action="store_true", help="actually append the key")
    args = parser.parse_args()

    values = load_env()
    host = values.get("SOURCE_HOST", "")
    user = values.get("SOURCE_USER", "root")
    port = int(values.get("SOURCE_PORT", "22") or "22")
    password = values.get("SOURCE_PASSWORD", "")
    key_value = values.get("SOURCE_SSH_KEY", "")

    if not host:
        print("SOURCE_HOST is required", file=sys.stderr)
        return 2
    if not password:
        print("SOURCE_PASSWORD is required for bootstrap", file=sys.stderr)
        return 2
    if not key_value:
        print("SOURCE_SSH_KEY is required", file=sys.stderr)
        return 2

    private_key = expand_local_path(key_value)
    pub_path = public_key_path(private_key)
    if not pub_path.exists():
        print(f"public key not found: {pub_path}", file=sys.stderr)
        return 2

    public_key = pub_path.read_text(encoding="utf-8").strip()
    if not public_key.startswith(("ssh-ed25519 ", "ssh-rsa ", "ecdsa-sha2-")):
        print(f"unsupported or invalid public key: {pub_path}", file=sys.stderr)
        return 2

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        hostname=host,
        port=port,
        username=user,
        password=password,
        timeout=10,
        banner_timeout=20,
        auth_timeout=10,
        look_for_keys=False,
        allow_agent=False,
    )

    code, out, err = run(client, "hostname && id -un")
    if code != 0:
        print(err or out, file=sys.stderr)
        client.close()
        return code

    print("Connected to source:")
    print(out.strip())

    remote_key = shell_single_quote(public_key)
    check_cmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && grep -qxF " + remote_key + " ~/.ssh/authorized_keys"
    code, _, _ = run(client, check_cmd)
    if code == 0:
        print("Public key is already installed.")
        client.close()
        return 0

    if not args.execute:
        print("Dry run only. Re-run with --execute to append the public key.")
        client.close()
        return 0

    append_cmd = (
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys "
        f"&& printf '%s\\n' {remote_key} >> ~/.ssh/authorized_keys "
        "&& chmod 600 ~/.ssh/authorized_keys"
    )
    code, out, err = run(client, append_cmd)
    client.close()
    if code != 0:
        print(err or out, file=sys.stderr)
        return code

    print("Public key installed on source.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
