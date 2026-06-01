# Ansible — VPS Migration Playbooks

Operator reference for rebuilding a fresh OVH Ubuntu VPS and migrating a
self-hosted Docker homelab onto it. Read this first before touching anything.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Two-Clone Model](#2-two-clone-model)
3. [Prerequisites](#3-prerequisites)
4. [Inventory & Connection Phases](#4-inventory--connection-phases)
5. [File Layout](#5-file-layout)
6. [group_vars Reference](#6-group_vars-reference)
7. [Run Order](#7-run-order)
8. [How Data Is Migrated](#8-how-data-is-migrated)
9. [Gotchas / Design Notes](#9-gotchas--design-notes)
10. [Manual Cutover Checklist](#10-manual-cutover-checklist)
11. [Verification After Each Phase](#11-verification-after-each-phase)
12. [Troubleshooting](#12-troubleshooting)
13. [Rehearse First](#13-rehearse-first)

---

## 1. Overview

**What this migrates:** seven self-hosted Docker stacks running on an OVH Ubuntu
VPS, managed as individual Compose projects under `/home/bharani/containers/`.

| Stack | Role | DB engine |
|---|---|---|
| nginx | Nginx Proxy Manager (reverse proxy, TLS) | MariaDB (jc21/mariadb-aria:10.11.5), container `mariadb` |
| registry | OCI Docker registry + UI + regbot | none (OCI blobs on disk) |
| infisical | Secrets manager | **external** Neon cloud PostgreSQL + local Redis (`infisical-redis`) |
| vaultwarden | Bitwarden-compatible password vault | SQLite (`vw-data/`) |
| gmailit | SimpleLogin self-hosted email alias service | PostgreSQL 12.1, container `sl-db` |
| portainer | Docker management UI | none |
| tunnel | Cloudflare Tunnel (`cloudflared`) | none |

**Goal:** provision a fresh box from scratch and move all stateful data with a
brief planned downtime on the old box, then flip DNS.

**Scope of Ansible:** Ansible owns the *host layer* — OS packages, users,
Docker, tooling (age, sops), the repo clone, and orchestrating the
dump/transfer/restore sequence. It calls each stack's `Makefile` target (`make
up`) to start containers, but does **not** own anything *inside* Docker — secret
encryption/decryption (sops + age + Makefiles do that), application config, or
image builds. DNS/mail cutover is manual.

Ansible is agentless and runs from a **control node**; no agent is installed on
the target.

---

## 2. Two-Clone Model

There are two independent clones of this repository:

| Clone | Where | Purpose |
|---|---|---|
| **Control-node clone** | Your local machine (Linux or WSL) | The directory you `cd` into and run `ansible-playbook` from |
| **Target clone** | `/home/bharani/containers/` on the new VPS | Made by the `repo` role during bootstrap; used by `make up` and sops at runtime |

The control node must be **Linux or WSL** — `ansible-playbook` does not run
natively on Windows.

The two clones stay in sync via git. The target clone is owned by `bharani` so
that `make up` works without sudo.

---

## 3. Prerequisites

### One-time setup (do this before any migration)

**Tailscale**

- A Tailscale tailnet with a device policy that includes a tagged machine tag,
  e.g. `tag:vps`.
- An SSH `accept` rule (NOT `check`) in the tailnet ACL so non-interactive
  Ansible runs are not blocked waiting for a browser confirmation:

  ```json
  { "action": "accept", "src": ["tag:admin"], "dst": ["tag:vps"], "users": ["autogroup:nonroot"] }
  ```

- A reusable or ephemeral **tagged auth key** generated from the Tailscale admin
  console (tagged with whatever tag the new VPS will wear).

**Infisical**

- A **Universal-Auth machine identity** in the Infisical project with Viewer
  access.
- The GitHub deploy key (ED25519 private key, no passphrase) stored as secret
  `GITHUB_DEPLOY_KEY` in that project, environment `prod`.
- The Infisical instance URL (`infisical_domain`) must be reachable from the new
  VPS during bootstrap — this is the URL of the *old* box's Infisical stack,
  before the DNS cutover.

**age key**

- The age **private** key file backed up to your control node
  (e.g. `~/.config/age/keys.txt`). The matching public key is the recipient in
  `ansible/.sops.yaml` and `ansible/recipients.txt`:

  ```
  age1qdp07v8r3gjgv0k8ehmlltdhljdtsl2wsnfqrhjkvxx9ndaptaxseew0cz
  ```

**Control node packages**

```bash
pip install ansible-core
ansible-galaxy collection install -r ansible/requirements.yml
# requires: ansible.posix >= 1.5.0 (synchronize module)
#           community.sops >= 1.6.0 (sops vars plugin for secrets.sops.yaml)
```

### Per-migration runtime overrides (non-secret, all have defaults)

The three secret vars (`infisical_client_id`, `infisical_client_secret`,
`tailscale_authkey`) are now loaded automatically from
`group_vars/all/secrets.sops.yaml` — see [Migration secrets (sops/age)](#migration-secrets-sopsage) below.

The path vars below have sensible defaults in `group_vars/all/main.yml` and
only need `-e` if your control-node layout differs from the defaults.

| Variable | Default | What it is |
|---|---|---|
| `age_key_src` | `~/.config/age/keys.txt` | Local filesystem path to your age **private** key file |
| `ssh_pubkey_path` | `~/.ssh/id_ed25519.pub` | Local path to the control-node SSH **public** key — installed into `bharani`'s `authorized_keys` |
| `old_box_pubkey_path` | `~/.ssh/old_box.pub` | Local path to the old box's `bharani` SSH **public** key — needed so `restore.yml`'s rsync push from old→new is authorized |

### Migration secrets (sops/age)

`infisical_client_id`, `infisical_client_secret`, and `tailscale_authkey` are
stored in `group_vars/all/secrets.sops.yaml`, encrypted with age. The
`community.sops` vars plugin auto-decrypts this file at play time using the age
private key already on the control node (`~/.config/age/keys.txt` by default).

To populate and encrypt the file before the first run:

```bash
cd ansible && sops group_vars/all/secrets.sops.yaml
```

sops reads the `secrets\.sops\.ya?ml$` creation rule from `ansible/.sops.yaml`
and encrypts all values with the age recipient. **The file must be
sops-encrypted before committing — never commit the plaintext `REPLACE_ME`
template.**

> **Note on `tailscale_authkey`:** Tailscale auth keys are ephemeral by
> default (one-time use). You must re-encrypt a fresh key into
> `secrets.sops.yaml` before each full migration run, unless you generate a
> reusable key from the Tailscale admin console.

---

## 4. Inventory & Connection Phases

File: `ansible/inventory/hosts.yml`

```
all:
  children:
    old_vps:       bharani@<tailnet-hostname>:2281
    new_vps:       bharani@<tailnet-hostname>:2281   ← Tailscale SSH (:22) or sshd (:2281)
    new_vps_raw:   root@<public-ip>:22
```

You fill in exactly **two fields** at arrival:

1. **Before Phase 1** — set `new_vps_raw.ansible_host` to the new server's
   public IP.
2. **After Phase 1** — set `new_vps.ansible_host` to the new box's Tailscale
   hostname (get it with `tailscale status` or `tailscale ip -4` on the box).

`old_vps.ansible_host` is the old box's Tailscale hostname — fill it in once and
leave it.

**Connection identity by phase:**

| Phase | Playbook | Target group | User | Port | How |
|---|---|---|---|---|---|
| 1 | bootstrap-tailscale.yml | new_vps_raw | root | 22 | public IP |
| 2 | bootstrap.yml | new_vps_raw | root | 22 | public IP |
| 3 | restore.yml | old_vps + new_vps | bharani | 2281 | Tailscale |
| 4 | deploy.yml | new_vps | bharani | 2281 | Tailscale |

After Phase 2 the hardened sshd on `:2281` is the primary path. Tailscale SSH
(`:22` via the tailnet) is also available as a break-glass path since the
`tailscale` role passes `--ssh` to `tailscale up`.

---

## 5. File Layout

```
ansible/
├── .sops.yaml                  # sops encryption rules (age recipient for *.env files)
├── recipients.txt              # age public key — used by sops encrypt
├── requirements.yml            # ansible-galaxy dependencies (ansible.posix)
├── site.yml                    # imports all four phases in order (full re-run)
│
├── bootstrap-tailscale.yml     # Phase 1: install + connect Tailscale (root@public-ip)
├── bootstrap.yml               # Phase 2: provision host — user, docker, tooling, repo (root)
├── restore.yml                 # Phase 3: dump → transfer → restore data (bharani via Tailscale)
├── deploy.yml                  # Phase 4: start all stacks in stack_order (bharani)
│
├── group_vars/
│   └── all/
│       ├── main.yml            # all non-secret shared variables (paths, versions, stack list)
│       └── secrets.sops.yaml   # sops/age-encrypted: infisical_client_id/secret, tailscale_authkey
│
├── inventory/
│   └── hosts.yml               # three hosts: old_vps, new_vps, new_vps_raw
│
└── roles/
    ├── tailscale/tasks/main.yml    # install tailscaled, tailscale up --ssh
    ├── common/tasks/main.yml       # apt packages (git make curl rsync …) + 2 GB swap
    ├── user/tasks/main.yml         # create bharani, sudo, authorized_keys, sshd :2281
    │   └── handlers/main.yml       # restart sshd handler
    ├── docker/tasks/main.yml       # docker-ce + compose plugin, add bharani to docker group
    ├── tooling/tasks/main.yml      # pinned age + sops binaries to /usr/local/bin/
    ├── secrets/tasks/main.yml      # copy age private key, symlink for sops discovery
    ├── repo/tasks/main.yml         # install Infisical CLI, fetch deploy key, git clone
    ├── db_dump/tasks/main.yml      # stop stacks, pg_dumpall / mariadb-dump, stop blob stacks
    ├── db_restore/tasks/main.yml   # start DB service, wait healthy, load dump, make up
    └── stacks/tasks/main.yml       # make up for each stack in stack_order; tunnel last
```

---

## 6. group_vars Reference

Files: `ansible/group_vars/all/main.yml` (plaintext) and `ansible/group_vars/all/secrets.sops.yaml` (sops/age-encrypted)

| Variable | Value / Default | Notes |
|---|---|---|
| `migration_freeze` | `true` | Set to `false` after the migration completes to allow deploys |
| `containers_dir` | `/home/bharani/containers` | Repo clone location on the host |
| `container_data_dir` | `/home/bharani/container-data` | Persistent data root |
| `dumps_dir` | `/home/bharani/dumps` | SQL dump output directory |
| `vps_user` | `bharani` | Non-root user created by the `user` role |
| `home_dir` | `/home/bharani` | Derived from `vps_user` |
| `repo_url` | `git@github.com:bek42/containers-vps-bnitturi.git` | SSH clone URL |
| `repo_branch` | `main` | Branch the `repo` role checks out |
| `age_version` | `1.2.1` | Pinned age binary version |
| `sops_version` | `3.13.1` | Pinned sops binary version |
| `ssh_port` | `2281` | Port the hardened sshd listens on after bootstrap |
| `swap_file` | `/swapfile` | Swap file path |
| `swap_size` | `2G` | Swap file size |
| `infisical_domain` | `CHANGEME` | URL of the Infisical instance (old box, pre-cutover) |
| `infisical_project_id` | `CHANGEME` | Infisical project ID |
| `infisical_env` | `prod` | Infisical environment name |
| `stack_order` | nginx, registry, infisical, vaultwarden, gmailit, portainer, tunnel | Deploy order; nginx first (shared-proxy), tunnel last |
| `stateful_db_stacks` | see file | Per-stack migration config (compose_file, engine, db_container …) |
| **Path overrides — defaults shown; pass `-e` only if your layout differs:** | | |
| `age_key_src` | `~/.config/age/keys.txt` | Local path to age private key; override with `-e` if needed |
| `ssh_pubkey_path` | `~/.ssh/id_ed25519.pub` | Local path to control-node SSH public key; override with `-e` if needed |
| `old_box_pubkey_path` | `~/.ssh/old_box.pub` | Local path to old box's `bharani` public key; override with `-e` if needed |
| **In `secrets.sops.yaml` (sops/age-encrypted — never plaintext in git):** | | |
| `tailscale_authkey` | *(encrypted)* | Ephemeral Tailscale auth key — re-encrypt before each run |
| `infisical_client_id` | *(encrypted)* | Universal-auth client ID for Infisical |
| `infisical_client_secret` | *(encrypted)* | Universal-auth client secret for Infisical |

---

## 7. Run Order

### Step 0 — Fill in inventory

```yaml
# ansible/inventory/hosts.yml
new_vps_raw:
  ansible_host: "1.2.3.4"          # ← new server's public IP

old_vps:
  ansible_host: "old-vps.tail…ts.net"   # ← old box's Tailscale hostname (fill once)
```

Install collection dependencies:

```bash
cd ansible/
ansible-galaxy collection install -r requirements.yml
```

---

### Phase 1 — Install Tailscale (root over public IP)

```bash
ansible-playbook bootstrap-tailscale.yml
```

After it completes, get the new box's Tailscale address:

```bash
# on the new box
tailscale ip -4
# or
tailscale status
```

Update `inventory/hosts.yml`:

```yaml
new_vps:
  ansible_host: "new-vps.tail…ts.net"   # ← fill in now
```

---

### Phase 2 — Provision the host (root over public IP)

```bash
ansible-playbook bootstrap.yml \
  -e age_key_src=~/.config/age/keys.txt \
  -e ssh_pubkey_path=~/.ssh/id_ed25519.pub \
  -e old_box_pubkey_path=~/.ssh/old_box.pub
```

> The `-e` path flags are optional if your control-node layout matches the
> defaults in `group_vars/all/main.yml`. `infisical_client_id`,
> `infisical_client_secret`, and `tailscale_authkey` are loaded automatically
> from `secrets.sops.yaml`.

Roles applied in order: `common` → `user` → `docker` → `tooling` → `secrets` → `repo`.

> **WARNING:** The `user` role writes `/etc/ssh/sshd_config.d/99-hardening.conf`
> (Port 2281, no root login, no password auth) and restarts sshd. Keep a second
> terminal open with an active session on the box (console/VNC) until you
> confirm `ssh bharani@<tailscale-host> -p 2281` works. After that, root login
> is permanently disabled.

---

### Phase 3 — Migrate data (bharani:2281 via Tailscale)

```bash
ansible-playbook restore.yml
```

Three plays in sequence:
1. **old_vps** — `db_dump` role (stop stacks, dump postgres + mariadb, stop blob stacks)
2. **new_vps** — inline transfer tasks (rsync old→new over Tailscale, data never touches the control node)
3. **new_vps** — `db_restore` role (start DB services, wait healthy, load dumps, `make up`)

> restore.yml must complete successfully before running deploy.yml.

---

### Phase 4 — Deploy all stacks (bharani:2281 via Tailscale)

```bash
ansible-playbook deploy.yml
```

Runs `make up` for each stack in `stack_order`. `make up` is idempotent — stacks
already started by `restore.yml` are left running. nginx always starts first
(creates `shared-proxy`). The `tunnel` stack is started last after stopping
`cloudflared` on the old box.

---

### Full re-run (all phases)

```bash
ansible-playbook site.yml \
  -e age_key_src=~/.config/age/keys.txt \
  -e ssh_pubkey_path=~/.ssh/id_ed25519.pub \
  -e old_box_pubkey_path=~/.ssh/old_box.pub
```

> The `-e` path flags are optional if your layout matches the defaults.
> All three secret vars are loaded from `secrets.sops.yaml`.

`site.yml` imports all four playbooks in order. Requires inventory to be fully
filled in first.

---

## 8. How Data Is Migrated

### Which stacks migrate which way

| Stack | Engine | Migration method |
|---|---|---|
| nginx | mariadb | Stop full stack → start only `db` service → `mariadb-dump --lock-tables` → rsync dump → load into fresh container |
| gmailit | postgres | Stop full stack → start only `postgres` service → `pg_dumpall` → rsync dump → `psql` restore |
| vaultwarden | sqlite | Stop whole compose → rsync `container-data/vaultwarden/` cold → `make up` |
| registry | blob (OCI layers) | Stop whole compose → rsync `container-data/registry/` cold → `make up` |
| infisical | external postgres + local redis | **Not migrated by this playbook** — see open items below |
| portainer | none | `make up` only |
| tunnel | none | `make up` only (old cloudflared stopped first) |

### db_dump (on old_vps)

1. Stop the entire stack for each postgres/mariadb stack (halts all writes).
2. Start only the database service (`db` for nginx / `postgres` for gmailit).
3. Dump:
   - **postgres** (gmailit): `pg_dumpall -U postgres` → `dumps/gmailit.sql`
   - **mariadb** (nginx): `mariadb-dump --all-databases --lock-tables` using
     `$MYSQL_ROOT_PASSWORD` from the container environment → `dumps/nginx.sql`
     (Aria tables are non-transactional; `--single-transaction` is not safe for them).
4. Stop blob stacks (vaultwarden, registry) cold so data is quiescent for rsync.

### Transfer (old_vps → new_vps, no control-node hop)

`ansible.posix.synchronize` with `mode: push` and `delegate_to: old_vps` means
rsync runs **on the old box** and pushes directly to the new box over the
Tailscale network. The control machine is never in the data path.

Two rsync calls:
- `dumps/` — SQL dump files
- `container-data/` — persistent data, with two directories **excluded**:
  - `/gmailit/db` — PostgreSQL data dir for `sl-db`; moved via dump/restore
  - `/ngnix/mariadb-aria` — MariaDB data dir for `mariadb`; moved via dump/restore

  These are excluded because copying their raw on-disk files alongside a dump
  restore would produce "database already exists" conflicts and duplicated state.
  vaultwarden (`vw-data/`) and registry blob layers are **not** excluded — they
  are the cold-copy stacks.

### db_restore (on new_vps)

For postgres and mariadb stacks:
1. Start only the DB service (`sops exec-env … docker compose up -d <service>`).
2. Wait for it to be healthy:
   - postgres: `pg_isready -U postgres` (up to 12 × 5 s = 60 s)
   - mariadb: `mysqladmin ping` (up to 12 × 5 s = 60 s)
3. Load the dump via stdin (`psql` / `mariadb`). For postgres, `pg_dumpall`
   output includes `CREATE ROLE` statements — these emit "role already exists"
   notices on a non-empty cluster; this is expected and not an error. Do **not**
   add `ON_ERROR_STOP` — it would abort on those notices.
4. `make up` to start the full stack.

For blob stacks (vaultwarden, registry): data was rsynced in the transfer step;
`make up` is all that's needed.

### migration_freeze

`migration_freeze: true` in `group_vars/all.yml` is a guard variable you can
check in deploy scripts to prevent accidental production deploys before the
restore completes. Set it to `false` after the cutover is confirmed healthy.
The freeze represents the brief planned downtime window on the old box.

### Open item — infisical

infisical is **not in `stateful_db_stacks`** and is not migrated by this
playbook. Before cutover, resolve:

1. **Neon DB** — infisical's postgres is external (Neon cloud, connected via
   `DB_CONNECTION_URI` in `infisical.env`). Does the Neon project need migration
   (Neon branching / `pg_dump` of the Neon endpoint), or does the new box simply
   reconnect to the same Neon project? Confirm the Neon DB accepts connections
   from the new VPS IP.
2. **Redis** — `container-data/infisical/redis` is rsynced as-is (not excluded).
   Decide whether Redis session/cache data must survive or whether users can
   re-authenticate after cutover.
3. If Redis state must be preserved **and** you need explicit stop/start control,
   add infisical to `stateful_db_stacks` with `engine: blob`.

---

## 9. Gotchas / Design Notes

**Always use `make up`, never bare `docker compose`**

Every stack's `Makefile` wraps compose in `sops exec-env <stack>.env --` to
inject decrypted secrets before starting containers. Running `docker compose up`
directly bypasses secret injection and the containers start with empty env vars.

**The `ngnix` typo in container-data**

The nginx stack writes persistent data to `/home/bharani/container-data/ngnix/`
(deliberate typo from the original setup). Both the compose file volume mounts
and the rsync exclude list in `restore.yml` use this spelling. Keep it identical
on both boxes — renaming it would break the volume mounts.

**docker group membership**

`bootstrap.yml` adds `bharani` to the `docker` group, but group membership only
takes effect on the **next login session**. This is why `restore.yml` and
`deploy.yml` target `new_vps` (a fresh SSH connection) rather than continuing
from the `new_vps_raw` session — by then bharani's docker access is active.

**Ubuntu 22.04+ socket-activated sshd**

On Ubuntu 22.04 and later, `ssh.socket` owns the listening port. The `Port`
directive in `sshd_config.d/` is ignored until `ssh.socket` is disabled, because
systemd creates the socket before sshd starts and sshd never calls `bind()`. The
`user` role:
1. Disables and stops `ssh.socket` (hands port binding back to `ssh.service`).
2. Writes `/etc/ssh/sshd_config.d/99-hardening.conf` with `Port 2281`.
3. Restarts `ssh.service`, which now binds 2281.

Verify `:2281` is reachable from a second terminal **before** the handler fires
and the root session drops.

**Tailscale SSH must be `accept`, not `check`**

If the tailnet SSH policy uses `action: "check"`, Tailscale requires browser-based
identity confirmation before allowing the connection. This hangs non-interactive
Ansible runs indefinitely. The policy rule must use `action: "accept"`.

**infisical's postgres is external — not migrated here**

The infisical Compose stack has no local postgres container. Its database lives
on a Neon cloud endpoint referenced by `DB_CONNECTION_URI`. The new VPS will
reconnect to that same endpoint after cutover. Verify the Neon project allows
the new box's egress IP before flipping DNS. See the open item in §8.

**`pg_dumpall` restore tolerates "role already exists" noise**

`pg_dumpall` output includes `CREATE ROLE postgres` (and any other roles). On a
freshly initialised PostgreSQL container the `postgres` superuser already exists,
so this statement emits a notice:

```
ERROR:  role "postgres" already exists
```

This is just a notice, not a fatal error, and psql continues. Do **not** pipe
through `--set ON_ERROR_STOP=1` — it would abort the entire restore on this
expected notice.

---

## 10. Manual Cutover Checklist

Run these steps after `deploy.yml` completes and before announcing the migration.

- [ ] **Stop old cloudflared** — `deploy.yml` does this automatically as part of
      starting the `tunnel` stack. Verify the old box's tunnel container is
      stopped: `docker ps | grep cloudflared` should return nothing.
- [ ] **Flip DNS** — update A/AAAA records for all domains to the new VPS IP.
      If you use Cloudflare DNS, the tunnel handles routing for proxied records —
      focus on any non-proxied records (MX, PTR, SPF, DKIM, DMARC).
- [ ] **Reverse DNS (PTR)** — set the PTR record for the new IP to the hostname
      used in outgoing SMTP HELO. Do this in the OVH control panel.
- [ ] **Outbound port 25** — confirm the new OVH VPS allows outbound port 25.
      OVH blocks it by default on some plans; open a support ticket if needed.
      The gmailit/postfix stack binds ports 25 and 587.
- [ ] **SPF** — if the SPF record was tied to the old IP, update it.
- [ ] **DKIM / DMARC** — these are key-based and do not change with IP. Verify
      the DNS records are present and the DKIM key in
      `container-data/gmailit/secrets/dkim.key` matches the DNS TXT record.

**Per-stack verification after DNS propagates:**

- nginx Proxy Manager admin UI accessible
- vaultwarden login works; vault data present
- gmailit / SimpleLogin login works; aliases functional; send a test email
- infisical UI accessible; confirm the Neon DB accepted the new box's connection
- registry push/pull from the new box's IP
- portainer UI shows all containers healthy

---

## 11. Verification After Each Phase

### After Phase 1 (Tailscale)

```bash
# Confirm box is on the tailnet
tailscale status           # run on the new box or from tailscale admin console

# Confirm Tailscale SSH works
ssh root@<tailscale-hostname>   # or bharani@ if already exists
```

### After Phase 2 (bootstrap)

```bash
# Control-node SSH via Tailscale
ssh bharani@<tailscale-hostname> -p 2281

# Root must be refused
ssh root@<tailscale-hostname> -p 2281   # should get "Permission denied"

# Confirm docker works in bharani's session
ssh bharani@<tailscale-hostname> -p 2281 'docker ps'

# age and sops installed
ssh bharani@<tailscale-hostname> -p 2281 'age --version && sops --version'

# Repo cloned
ssh bharani@<tailscale-hostname> -p 2281 'ls ~/containers/'
```

### After Phase 3 (restore)

```bash
ssh bharani@<tailscale-hostname> -p 2281

# nginx (mariadb) — check NPM tables
docker exec mariadb mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" npm -e "SHOW TABLES;"

# gmailit (postgres) — check user count or alias count
docker exec sl-db psql -U postgres -c "\dt"

# vaultwarden data present
ls ~/container-data/vaultwarden/

# registry blobs present
ls ~/container-data/registry/
```

### After Phase 4 (deploy)

```bash
# All containers should be Up
docker ps --format 'table {{.Names}}\t{{.Status}}'

# No containers in Restarting or Exited state
docker ps -a --filter status=exited
docker ps -a --filter status=restarting
```

---

## 12. Troubleshooting

**Cannot reach port 2281 after bootstrap**

Cause: `ssh.socket` was not disabled before the sshd restart, so systemd still
owns port 22 and the new `Port 2281` line is ignored.

Fix: connect via the console/VNC, then:
```bash
sudo systemctl disable --now ssh.socket
sudo systemctl restart ssh
```

**git clone fails in the `repo` role**

Possible causes:
- Infisical is unreachable from the new VPS (`infisical_domain` is wrong or the
  old box is down).
- The universal-auth credentials (`infisical_client_id` / `infisical_client_secret`)
  are incorrect.
- The `GITHUB_DEPLOY_KEY` secret does not exist in the project/env specified.
- `~/.ssh/id_ed25519` was not written (check with `no_log: false` temporarily).

**Ansible hangs on connect after Phase 1**

Cause: The tailnet SSH ACL rule uses `action: "check"` instead of `action: "accept"`.
The Tailscale SSH daemon is waiting for a browser confirmation.

Fix: change the ACL rule to `action: "accept"`, then `tailscale policy apply`.

**rsync returns "Permission denied" during restore.yml transfer**

Cause: The old box's `bharani` SSH public key was not added to the new box's
`authorized_keys` (the `old_box_pubkey_path` was wrong or missing in Phase 2).

Fix: manually add the old box's public key to `~bharani/.ssh/authorized_keys` on
the new box, then re-run `restore.yml`.

**infisical container exits immediately after `make up`**

Cause: The Neon cloud DB is unreachable from the new VPS IP. Neon may require an
IP allowlist entry.

Fix: find the new box's egress IP (`curl -s ifconfig.me`), add it to the Neon
project's IP allowlist, then `make up` again.

**MariaDB restore emits errors**

Aria tables use `--lock-tables` (not `--single-transaction`). If the restore
fails mid-stream, `mariadb-dump` output includes a `LOCK TABLES … WRITE`
statement at the top of each table. Drop the database and recreate it before
retrying:
```bash
docker exec mariadb mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE npm; CREATE DATABASE npm;"
docker exec -i mariadb mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" < ~/dumps/nginx.sql
```

---

## 13. Rehearse First

Before running against the real old box, do a full dry run:

1. Spin up a throwaway Ubuntu VPS (or a Multipass VM) to act as `new_vps_raw`.
2. Point `old_vps` at a second VM with representative dummy data.
3. Run all four phases end-to-end and confirm every verification check passes.
4. Destroy both VMs.

This catches Tailscale policy issues, Infisical credential problems, and
rsync/ssh trust issues without any risk to production data.
