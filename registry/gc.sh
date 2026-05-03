#!/bin/bash
# Runs weekly via cron to reclaim disk space after regbot deletes tags
docker exec registry registry garbage-collect \
  --delete-untagged \
  /etc/docker/registry/config.yml >> /var/log/registry-gc.log 2>&1