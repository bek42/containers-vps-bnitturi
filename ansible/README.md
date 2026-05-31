# Ansible – VPS Migration Playbooks

## Overview

| Playbook | Target | Connection | Purpose |
|---|---|---|---|
| `bootstrap-tailscale.yml` | `new_vps_raw` | root:22 (public IP) | Install & connect Tailscale |
| `bootstrap.yml` | `new_vps_raw` | root:22 (public IP) | Provision user, docker, tooling, repo |
| `restore.yml` | `old_vps` + `new_vps` | bharani:2281 (Tailscale) | Dump, transfer & restore data |
| `deploy.yml` | `new_vps` | bharani:2281 (Tailscale) | Start all stacks in order |
| `site.yml` | all of the above | — | Import all phases in sequence |

---

## Run Order

### 0. Prerequisites

```bash
cd ansible/
ansible-galaxy collection install -r requirements.yml
```

Fill in `inventory/hosts.yml`:
- `new_vps_raw.ansible_host` — new server's public IP
- `old_vps.ansible_host` — old server's Tailscale hostname

### Phase 1 — Install Tailscale (root over public IP)

```bash
ansible-playbook bootstrap-tailscale.yml \
  -e tailscale_authkey=tskey-auth-XXXXXXXXXXXX
```

Once complete, note the new box's Tailscale hostname/IP (`tailscale ip -4` on the box)
and set `new_vps.ansible_host` in `inventory/hosts.yml`.

### Phase 2 — Provision the host (root over public IP)

```bash
ansible-playbook bootstrap.yml \
  -e age_key_src=~/.config/age/keys.txt \
  -e ssh_pubkey_path=~/.ssh/id_ed25519.pub \
  -e old_box_pubkey_path=~/.ssh/old_box.pub
```

> **WARNING**: The `user` role changes the SSH port to **2281** and disables root login.
> Keep a second terminal open connected to the box (e.g. via console/VNC) until you
> confirm `ssh bharani@<new-tailscale-host> -p 2281` works.

After bootstrap, root login is disabled. All subsequent access is via
`bharani@<tailscale-host>:2281`.

### Phase 3 — Migrate data (bharani:2281 via Tailscale)

```bash
ansible-playbook restore.yml
```

This play:
1. Freezes the old box (stops stacks, creates DB dumps)
2. Rsyncs dumps + container-data over the Tailscale network
3. Loads dumps and starts stateful services on the new box

### Phase 4 — Deploy all stacks (bharani:2281 via Tailscale)

```bash
ansible-playbook deploy.yml
```

Starts every stack in `stack_order` (nginx → registry → infisical → vaultwarden →
gmailit → portainer → tunnel). `make up` is idempotent — stacks already running
from restore.yml are untouched. The Cloudflare tunnel on the old box is stopped
before the new tunnel container starts.

---

## Runtime `-e` Variables

| Variable | Phase | Description |
|---|---|---|
| `tailscale_authkey` | bootstrap-tailscale | Ephemeral one-time Tailscale auth key |
| `age_key_src` | bootstrap | Local path to the age **private** key file |
| `ssh_pubkey_path` | bootstrap | Local path to control-node SSH **public** key |
| `old_box_pubkey_path` | bootstrap | Local path to old box's `bharani` SSH **public** key (needed so restore.yml rsync-push works) |

These four are intentionally set to `CHANGEME` in `group_vars/all.yml` — never
commit real values.

---

## Stack Start Order

```
nginx       ← creates shared-proxy Docker network
registry    ← joins shared-proxy
infisical   ← joins shared-proxy
vaultwarden
gmailit
portainer
tunnel      ← last: Cloudflare credential is unique; old box stops first
```

---

## Notes

- **`container-data/ngnix`** (deliberate typo) — the nginx stack writes to this
  directory; keep the spelling identical on both boxes.
- **docker group** — the `docker` role adds bharani to the docker group, but the
  membership is only active on a **new login session**. `deploy.yml` targets
  `new_vps` (not `new_vps_raw`) so it connects as a fresh session and the group
  is active.
- **git deploy key** — the `repo` role clones via SSH (`git@github.com:...`).
  Either place a deploy key at `~bharani/.ssh/id_ed25519` before running
  bootstrap, or enable SSH agent forwarding in your Ansible config.
- **infisical postgres** — infisical uses an external Neon DB (see TODO in
  `group_vars/all.yml`). Its Redis data lives at
  `container-data/infisical/redis` and is rsynced as-is; resolve the Neon
  migration separately.
