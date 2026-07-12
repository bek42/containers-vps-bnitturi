#!/bin/bash
# Runs weekly via bharani's crontab to reclaim disk space after regbot
# deletes tags. Logging is piped through `tee` rather than a plain `>>`
# redirect: a plain redirect has to successfully open the log file
# *before* the command even starts, so a full disk (which can make the
# log file itself unwritable) silently prevented GC from ever running --
# exactly what happened on 2026-07-12, when the registry filled to 100%
# and the weekly job left no trace at all. Piping through tee means the
# cleanup command always runs even if the log write fails.
LOG=/home/bharani/container-data/registry/gc.log
{
  echo "=== $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  docker exec registry registry garbage-collect --delete-untagged /etc/distribution/config.yml
  echo "=== done: $(df -h / | tail -1) ==="
} 2>&1 | tee -a "$LOG" || true
