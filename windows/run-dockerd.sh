#!/usr/bin/env bash
set -euo pipefail

# WSL without systemd needs a long-lived wsl.exe host process.
# The Windows task launches this file in the foreground inside a hidden process.
exec dockerd --host=unix:///var/run/docker.sock >>/var/log/pennyroyal-dockerd.log 2>&1
