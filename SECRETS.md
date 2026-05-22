# Secrets Management — sops + age

This repo encrypts all secrets in place using **age** for the asymmetric crypto and **sops** as the file-format layer that keeps encrypted `.env` files diffable in git. Day-to-day you run `make` commands inside each stack folder — sops decrypts in memory, hands the values to `docker compose`, and the plaintext never touches disk.

## Why this exists

- Secrets live encrypted in git, so the repo alone is enough to redeploy on a new VPS — no separate "secrets folder" to back up or copy around.
- `git diff` shows you *which secret* was rotated (sops partial encryption preserves the keys and the file structure), giving a real audit trail.
- One age private key is the only thing you need to keep safe. Lose the repo and you can re-clone; lose the key and the encrypted files are unrecoverable, forever.

## Two patterns in this repo

| Pattern | When | Used by |
|---|---|---|
| **sops + age** (in-place, partial encryption) | `.env` files where you want diff visibility | `infisical/`, future env-file stacks |
| **plain age** (opaque whole-file encryption) | single-secret files with no structure (Docker secrets, credential JSONs) | `nginx/` (mariadb passwords) |

Both share the same age keypair — only the wrapping tool differs.

## Prerequisites

- `age` ≥ 1.2
- `sops` ≥ 3.13
- `make` (any GNU make)
- `docker` and `docker compose`

All available on Ubuntu 24.04 except `sops`, which needs the GitHub release binary.

---

## Migration recipe — bringing it up on a new VPS

This is the section you'll actually need on a fresh box.

### 1. Install the tools

```bash
sudo apt update
sudo apt install -y age make
```

For sops (apt usually doesn't have it or has a stale version):

```bash
SOPS_VER=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest \
  | grep tag_name | cut -d'"' -f4 | sed 's/^v//')
curl -LO "https://github.com/getsops/sops/releases/download/v${SOPS_VER}/sops-v${SOPS_VER}.linux.amd64"
sudo mv sops-v${SOPS_VER}.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops
sops --version --check-for-updates
```

Confirm all three are on the PATH:

```bash
age --version
sops --version --check-for-updates
make --version
```

### 2. Restore your age private key

From your password manager, retrieve the key file contents you backed up. Place it on disk:

```bash
mkdir -p ~/.config/age
nano ~/.config/age/keys.txt        # paste the entire contents, including the comment lines
chmod 600 ~/.config/age/keys.txt
```

The file should contain three lines — a `# created:` comment, a `# public key:` comment, and an `AGE-SECRET-KEY-1...` line.

Verify by deriving the public key from the private key:

```bash
age-keygen -y ~/.config/age/keys.txt
```

That should print your `age1...` public key. It must match the value in `recipients.txt` at the repo root and in `.sops.yaml`. If it doesn't, you placed the wrong key.

### 3. Symlink the key so sops can find it

```bash
mkdir -p ~/.config/sops/age
ln -sf ~/.config/age/keys.txt ~/.config/sops/age/keys.txt
ls -la ~/.config/sops/age/keys.txt
```

(sops looks at `~/.config/sops/age/keys.txt` by default; age uses `~/.config/age/keys.txt`. The symlink keeps one source of truth — change one, change "both.")

### 4. Clone the repo

```bash
git clone <repo-url> ~/containers
cd ~/containers
```

### 5. Bring up each stack

For every stack folder that has a `Makefile`:

```bash
cd ~/containers/infisical && make up
cd ~/containers/nginx     && make up
# ... repeat for each stack
```

`make up` handles decryption automatically — sops or age, depending on which pattern the stack uses. You should not need to `age --decrypt` or `sops --decrypt` by hand on a migration. If you find yourself wanting to, something is wrong with the Makefile setup.

That's the entire migration. No `~/secrets/` folder, no separate copy of credentials — the repo plus the age key is enough.

---

## How the pieces fit

```
~/.config/age/keys.txt           ← private key (your single point of failure)
~/.config/sops/age/keys.txt      ← symlink to above (so sops finds it)

~/containers/
├── .sops.yaml                   ← sops rules: which key, what to encrypt
├── recipients.txt               ← age public key (for the plain-age stacks)
├── nginx/                        # plain-age pattern (opaque secrets)
│   ├── Makefile
│   ├── docker-compose.yml
│   ├── ngix_maria_db.age         ← committed, age-encrypted
│   ├── ngix_maria_db_rt.age      ← committed, age-encrypted
│   └── .gitignore                ← blocks the plaintext twins
└── infisical/                    # sops pattern (structured env file)
    ├── Makefile
    ├── docker-compose.yml        ← uses `environment:` block, NOT env_file
    └── infisical.env             ← committed, encrypted in place (sops)
```

The `.sops.yaml` at the root declares the rules:

```yaml
creation_rules:
  - path_regex: '\.env$'
    age: age1qdp07v8r3gjgv0k8ehmlltdhljdtsl2wsnfqrhjkvxx9ndaptaxseew0cz
    unencrypted_regex: '^(SITE_URL|HOST|PORT|NODE_ENV|LOG_LEVEL)$'
```

The `unencrypted_regex` lists keys that stay plain inside the encrypted file — pure config like public URLs, ports, and log levels. Everything else gets encrypted. To keep additional config keys readable in git, add them to this regex.

---

## Day-to-day operations

### Editing an existing secret — `make edit`

From inside the stack folder (e.g. `~/containers/infisical/`):

```bash
make edit
```

This expands to `sops edit infisical.env`, which:

1. Decrypts the file to a temporary file in `/tmp/` (outside your repo).
2. Opens that temp file in `$EDITOR`.
3. Waits for you to save and close.
4. Re-encrypts the file in place, applying the same `.sops.yaml` rules.
5. Deletes the temp file.

Plaintext only ever exists in `/tmp/` during the edit session, and only the keys/values you changed appear in the resulting git diff.

**After editing, apply the change to the running container:**

```bash
make restart
```

Containers don't re-read env vars on the fly — they have to be recreated. `make restart` does `down` + `up`, which means sops decrypts again and the new values are passed to the new containers.

**Then commit:**

```bash
cd ~/containers
git add infisical/infisical.env
git commit -m "rotate AUTH_SECRET"
git push
```

The encrypted file changed when you saved in `sops edit`, so git sees a diff. Because of partial encryption, the diff actually shows you which key changed — the others stay as identical `ENC[...]` blobs. Real audit trail of secret rotations in the repo's history.

### Adding a NEW secret variable

The `sops exec-env` approach needs updates in **two** places (this is the tradeoff for "no plaintext on disk"):

1. **Add the value in `make edit`.** Inside the editor, add a line:
   ```
   SMTP_PASSWORD=actualpasswordhere
   ```
   Save and close — sops re-encrypts.

2. **Declare it in compose.** Edit `docker-compose.yml` and add the new variable to the `environment:` block:
   ```yaml
       environment:
         - DB_CONNECTION_URI
         - REDIS_URL
         - ENCRYPTION_KEY
         - AUTH_SECRET
         - SITE_URL
         - SMTP_PASSWORD       # new
   ```

3. **Apply and commit:**
   ```bash
   make restart
   cd ~/containers
   git add infisical/infisical.env infisical/docker-compose.yml
   git commit -m "add SMTP_PASSWORD"
   git push
   ```

If you skip step 2, sops will set the env var in the shell but compose won't forward it to the container. The `environment: - VAR` shorthand only passes through what's explicitly listed.

### Removing a secret variable

Reverse of adding:

1. `make edit` — delete the line from the env file, save.
2. Edit `docker-compose.yml` — remove the variable from `environment:`.
3. `make restart`
4. Commit both files.

### Restarting a stack

```bash
make restart        # down + up via make (always goes through sops/age)
```

### Stopping a stack

```bash
make down
```

### Inspecting state

The encrypted file on disk, as-is:

```bash
cat infisical.env
```

You'll see structure with secret values as `ENC[AES256_GCM,...]` blocks and config values (per `unencrypted_regex`) in plaintext, plus a `sops:` metadata footer.

To peek at the decrypted content without touching the file:

```bash
sops -d infisical.env | head -20
```

Plaintext goes to stdout. The file on disk stays encrypted.

To verify decryption works end-to-end (handy for testing the age key is in place):

```bash
sops -d infisical.env > /dev/null && echo "decryption OK"
```

### Editor configuration for `sops edit`

`sops edit` uses `$EDITOR`, defaulting to vim on Linux.

| Want | Command |
|---|---|
| Nano, one-off | `EDITOR=nano make edit` |
| Nano, persistent | Add `export EDITOR=nano` to `~/.bashrc` |
| VS Code over SSH | `EDITOR='code --wait' make edit` |
| VS Code, persistent | `export EDITOR='code --wait'` in `~/.bashrc` |

The `--wait` flag for VS Code is essential — without it, `code` returns immediately and sops thinks you're done editing before you've started.

---

## Per-stack setup — converting a new stack to sops

When you add a new stack with `.env` secrets, here's the conversion pattern. Use this when you have an existing stack with secrets in `~/secrets/<name>.env` and a compose file pointing at it.

### 1. Bring the plaintext into the stack folder

```bash
cd ~/containers/<stack>
cp ~/secrets/<name>.env .
chmod 600 <name>.env
```

### 2. Encrypt in place

The `.sops.yaml` rule for `*.env` will be picked up automatically:

```bash
sops --encrypt --in-place <name>.env
cat <name>.env       # verify: secrets as ENC[...], config plain, sops: footer present
```

### 3. Convert `docker-compose.yml` from `env_file` to `environment`

Find the block:

```yaml
env_file:
  - /home/bharani/secrets/<name>.env       # or ./<name>.env
```

Replace with one line per variable in the env file:

```yaml
environment:
  - DB_URL
  - API_KEY
  - SITE_URL
  # ... one entry per variable
```

The `- VAR` (no `=value`) shorthand tells compose to pass through whatever's in the calling shell's environment.

### 4. Create the Makefile in the stack folder

```bash
cat > Makefile <<'MAKEFILE'
.PHONY: up down restart edit

up:
	sops exec-env <name>.env 'docker compose up -d'

down:
	docker compose down

restart: down up

edit:
	sops edit <name>.env
MAKEFILE
```

**Critical:** recipe lines must start with a TAB, not spaces. The `<<'MAKEFILE'` quoted heredoc preserves tabs as you type them. Verify with `cat -A Makefile` — TABs render as `^I` at the start of each recipe line.

### 5. Test

```bash
docker compose down              # stop the old containers if running
make up
docker compose ps
docker compose logs --tail 30 <service-name>
```

You should see clean startup logs — no "Invalid environment variables" or "undefined" errors.

### 6. Commit

```bash
cd ~/containers
git add <stack>/<name>.env <stack>/docker-compose.yml <stack>/Makefile
git commit -m "<stack>: encrypt secrets with sops"
git push
```

After verifying the migration works on the new VPS end-to-end, you can delete `~/secrets/<name>.env` — the encrypted file in the repo is now the source of truth.

---

## The plain-age pattern (used by nginx)

For files that aren't structured `.env` (Docker secret files, credential JSONs), sops's partial-encryption benefit doesn't apply, so we use plain age with a two-file pattern:

- Encrypted file (committed): `<name>.age`
- Plaintext file (gitignored, materialized on demand): `<name>`

**Encrypt** (one-time, on setup):

```bash
age --encrypt --armor --recipients-file ../recipients.txt \
    --output <name>.age <name>
```

**Decrypt** (used by the Makefile before `docker compose up`):

```bash
age --decrypt --identity ~/.config/age/keys.txt \
    --output <name> <name>.age
```

The nginx Makefile handles the cycle automatically via a `find . -name '*.age'` loop that decrypts any encrypted file lacking a plaintext twin. See `nginx/Makefile` for the exact pattern. The local `nginx/.gitignore` ensures the plaintext versions are never staged.

---

## Troubleshooting

**`Invalid environment variables ... AUTH_SECRET ... received: 'undefined'`** — you ran `docker compose up` directly instead of `make up`. Without sops in the loop, the env vars are never set. Always use `make up` for stacks that wrap secrets through sops.

**`Error: failed to decrypt: no key could decrypt the data`** — sops can't find or use your age key. Check, in order:
1. `ls -la ~/.config/sops/age/keys.txt` — symlink exists
2. `cat ~/.config/age/keys.txt` — file is readable
3. `age-keygen -y ~/.config/age/keys.txt` — returns a public key
4. That key matches the recipient in `.sops.yaml` and `recipients.txt`

**`Makefile:N: *** missing separator. Stop.`** — recipe lines aren't tab-indented. Run `cat -A Makefile` — recipe lines must start with `^I`, not spaces. Recreate with a quoted heredoc to preserve tabs.

**`sops edit` opens the file and exits immediately, no actual editing** — your `$EDITOR` is exiting on launch (common with `code` without `--wait`). For VS Code over SSH use `EDITOR='code --wait' make edit`. For nano use `EDITOR=nano make edit`.

**Container starts but immediately exits with "missing required env var X"** — you added X to the env file via `make edit` but forgot to add `- X` to compose's `environment:` block. Add it and `make restart`.

**`git status` shows the encrypted file as modified but you didn't `make edit`** — sops touches the `lastmodified` field on every encrypt operation, even no-op ones. Either commit the timestamp-only change or `git checkout <file>` to revert.

**`sops exec-env` fails with "command not found: docker"** — sops doesn't always inherit the full PATH from your shell. If docker is in a non-standard location, run with the absolute path: `sops exec-env infisical.env '/usr/bin/docker compose up -d'`, or symlink docker into `/usr/local/bin`.

---

## Reference

### Key file locations

| Path | What it is | Backed up where |
|---|---|---|
| `~/.config/age/keys.txt` | Private age key | **Password manager** (single point of failure) |
| `~/.config/sops/age/keys.txt` | Symlink to private key | Not separately — symlink |
| `~/containers/recipients.txt` | Public key (used by plain-age stacks) | In git |
| `~/containers/.sops.yaml` | sops rules — recipient + regexes | In git |
| `~/containers/<stack>/Makefile` | Per-stack `make up/down/edit` wrapper | In git |

### Common commands

| Action | Command |
|---|---|
| Edit a secret | `make edit` (from stack folder) |
| Bring stack up | `make up` |
| Stop stack | `make down` |
| Restart stack after a secret change | `make restart` |
| Inspect encrypted file content | `cat <name>.env` |
| Peek at decrypted content | `sops -d <name>.env \| head` |
| Verify decryption works | `sops -d <name>.env > /dev/null && echo OK` |
| Show your public key | `age-keygen -y ~/.config/age/keys.txt` |
| Re-encrypt a manually-decrypted file | `sops --encrypt --in-place <name>.env` |
| Manually decrypt to disk (avoid if possible) | `sops --decrypt --in-place <name>.env` |

### Which tool for what

- **Routine secret edit** → `sops edit` (via `make edit`)
- **Inspecting current state** → `cat` (structure is readable thanks to partial encryption)
- **Decrypting to use** → `sops exec-env` (via `make up`)
- **Decrypting just to read** → `sops -d ... | less`
- **Encrypting a brand-new plaintext file** → `sops --encrypt --in-place`
- **Plain-age stacks (nginx)** → `age --encrypt` / `age --decrypt` directly; the Makefile wraps it

### Key rotation (advanced)

If you need to replace the age key (compromise, scheduled rotation):

1. Generate a new key: `age-keygen -o ~/.config/age/keys-new.txt`
2. Update `.sops.yaml` and `recipients.txt` with the new public key
3. For each sops-encrypted file: `sops updatekeys <file>` (re-encrypts the data key for the new recipient, doesn't touch your secret values)
4. For each age-encrypted file: decrypt with the old key, re-encrypt with the new key
5. Commit, push, distribute the new private key
6. Securely destroy the old key

Multiple recipients (e.g. teammate's key) can also be added to `.sops.yaml`'s `age:` field as a comma-separated list — sops re-encrypts the data key for everyone listed.
