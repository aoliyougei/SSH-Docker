# SSH Docker Container Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Debian 13 container that accepts public-key SSH connections as the unprivileged `aoliyougei` user and can execute Bash scripts with `curl` available.

**Architecture:** OpenSSH runs directly as PID 1 and reads `aoliyougei`'s authorized keys from the externally mounted `/etc/ssh/authorized_keys/aoliyougei` file. The image contains no user keys, passwords, sudo, entrypoint script, or process supervisor.

**Tech Stack:** Docker, Debian 13 slim, OpenSSH Server, Bash, curl, Kubernetes Secret volume

**Spec:** `docs/superpowers/specs/2026-04-13-ssh-container-design.md`

## Global Constraints

- Base image is `debian:13-slim`.
- Install only `openssh-server`, `bash`, `curl`, and `ca-certificates`, plus package-manager-resolved dependencies.
- SSH user is the unprivileged `aoliyougei` user with no `sudo` access.
- Permit public-key authentication only; disable password, keyboard-interactive, and root SSH login.
- Read keys only from `/etc/ssh/authorized_keys/%u`; do not use an environment variable or embed keys in the image.
- Run `/usr/sbin/sshd -D -e` as the foreground container process and expose TCP port 22.
- Do not place any real public or private key in the repository.
- All builds and executable verification run through the Docker API, never in the local workspace.

---

### Task 1: Build and verify the SSH container

**Files:**
- Create: `Dockerfile`
- Create: `sshd_config`
- Create: `k8s.yaml`

**Interfaces:**
- Consumes: a runtime-mounted OpenSSH-format public-key file at `/etc/ssh/authorized_keys/aoliyougei`
- Produces: an image listening on TCP 22; a Kubernetes Deployment and ClusterIP Service using Secret `ssh-authorized-keys`

- [ ] **Step 1: Create the minimal OpenSSH configuration**

Create `sshd_config`:

```text
Port 22
HostKey /etc/ssh/ssh_host_ed25519_key
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile /etc/ssh/authorized_keys/%u
AllowUsers aoliyougei
UsePAM no
PrintMotd no
Subsystem sftp internal-sftp
```

- [ ] **Step 2: Create the image definition**

Create `Dockerfile`:

```dockerfile
FROM debian:13-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-server bash curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --shell /bin/bash aoliyougei \
 && passwd -d aoliyougei \
 && mkdir -p /run/sshd /etc/ssh/authorized_keys \
 && chmod 755 /etc/ssh/authorized_keys

COPY sshd_config /etc/ssh/sshd_config

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
```

- [ ] **Step 3: Create the Kubernetes example**

Create `k8s.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ssh-box
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ssh-box
  template:
    metadata:
      labels:
        app: ssh-box
    spec:
      containers:
        - name: ssh-box
          image: ssh-box:latest
          ports:
            - name: ssh
              containerPort: 22
          volumeMounts:
            - name: authorized-keys
              mountPath: /etc/ssh/authorized_keys
              readOnly: true
      volumes:
        - name: authorized-keys
          secret:
            secretName: ssh-authorized-keys
            defaultMode: 0444
            items:
              - key: authorized_keys
                path: aoliyougei
---
apiVersion: v1
kind: Service
metadata:
  name: ssh-box
spec:
  selector:
    app: ssh-box
  ports:
    - name: ssh
      port: 22
      targetPort: ssh
```

Create the referenced Secret outside the manifest so no real key enters source control:

```bash
kubectl create secret generic ssh-authorized-keys \
  --from-file=authorized_keys="$HOME/.ssh/id_ed25519.pub"
```

- [ ] **Step 4: Build through the Docker API**

Stream the project build context to the Docker Engine and build the explicit local tag `ssh-box:test` using the Docker API build tool.

Expected: build exits successfully and the final image is tagged `ssh-box:test`.

- [ ] **Step 5: Generate an ephemeral test key without writing it to the project**

Create a temporary `debian:13-slim` helper container, install `openssh-client`, and run:

```bash
ssh-keygen -q -t ed25519 -N '' -f /tmp/id_ed25519
```

Keep both test-key files only in task-owned containers. Do not download them into the project.

Expected: `/tmp/id_ed25519` and `/tmp/id_ed25519.pub` exist in the helper container.

- [ ] **Step 6: Start the image with the test public key mounted read-only**

Create a task-owned test container from `ssh-box:test` with a read-only volume containing the helper container's `/tmp/id_ed25519.pub` at:

```text
/etc/ssh/authorized_keys/aoliyougei
```

Start the test container and inspect its logs.

Expected: `sshd` remains running and logs `Server listening on 0.0.0.0 port 22` or the IPv6 equivalent.

- [ ] **Step 7: Verify SSH, Bash, curl, identity, and lack of sudo**

From the helper container on the same task-owned Docker network, execute:

```bash
ssh -i /tmp/id_ed25519 \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  aoliyougei@ssh-box-test \
  'test "$(whoami)" = aoliyougei && command -v bash && command -v curl && ! command -v sudo'
```

Expected: exit status `0`; output includes paths for `bash` and `curl`, and no `sudo` path.

- [ ] **Step 8: Verify password and root login policy statically**

In the running test container, execute:

```bash
/usr/sbin/sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|authorizedkeysfile|allowusers) '
```

Expected output contains:

```text
permitrootlogin no
passwordauthentication no
kbdinteractiveauthentication no
pubkeyauthentication yes
authorizedkeysfile /etc/ssh/authorized_keys/%u
allowusers aoliyougei
```

- [ ] **Step 9: Clean up task-owned Docker resources**

Stop and remove the test and helper containers and remove the task-owned test network/volume. Keep the built `ssh-box:test` image as the requested build output.

Expected: no task-owned containers, test private keys, networks, or volumes remain.

- [ ] **Step 10: Record version-control status**

Run:

```bash
git status --short
```

Expected in the current workspace: Git reports that this directory is not a repository. Do not initialize a repository or create a commit unless the user requests it.
