#!/usr/bin/env python3
"""Ejecutor SSH no interactivo (Windows -> Linux) usando paramiko.

Uso:
    set WAPI_SSH_HOST=... ; set WAPI_SSH_USER=root ; set WAPI_SSH_PASS=...
    python __agent__/wapi/ssh_run.py "comando a ejecutar"

La contraseña NUNCA se escribe en disco: llega por variable de entorno.
Salida: stdout/stderr del remoto + "[exit=N]".
"""
import os
import sys
import warnings

warnings.filterwarnings("ignore")

import paramiko  # noqa: E402

HOST = os.environ.get("WAPI_SSH_HOST", "")
PORT = int(os.environ.get("WAPI_SSH_PORT", "22"))
USER = os.environ.get("WAPI_SSH_USER", "")
PASSWORD = os.environ.get("WAPI_SSH_PASS", "")
KEYFILE = os.environ.get("WAPI_SSH_KEY", "")


def main() -> int:
    if len(sys.argv) < 2:
        print("falta el comando", file=sys.stderr)
        return 2
    if not HOST or not USER:
        print("faltan WAPI_SSH_HOST / WAPI_SSH_USER", file=sys.stderr)
        return 2

    cmd = " ".join(sys.argv[1:])
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(
            hostname=HOST,
            port=PORT,
            username=USER,
            password=PASSWORD or None,
            key_filename=KEYFILE or None,
            timeout=25,
            banner_timeout=25,
            auth_timeout=25,
            look_for_keys=not PASSWORD,
            allow_agent=False,
        )
    except Exception as exc:  # noqa: BLE001
        print(f"[ssh] conexión fallida: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 3

    try:
        _, stdout, stderr = client.exec_command(cmd, timeout=180)
        out = stdout.read().decode("utf-8", "replace")
        err = stderr.read().decode("utf-8", "replace")
        code = stdout.channel.recv_exit_status()
    finally:
        client.close()

    if out:
        sys.stdout.write(out)
    if err:
        sys.stderr.write(err)
    print(f"[exit={code}]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())