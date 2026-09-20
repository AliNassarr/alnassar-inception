# Inception: The Definitive 0-to-100 Defense & Mastery Guide

Welcome to the comprehensive master guide for **Inception**. This guide is crafted to take you from knowing nothing about the codebase to understanding every architectural decision, line of code, Docker mechanism, and defense question so you can pass your peer evaluation with 100%.

---

# Table of Contents
1. [The Big Picture: Mental Model & Architecture](#1-the-big-picture-mental-model--architecture)
2. [Core Theoretical Concepts (Oral Exam Questions)](#2-core-theoretical-concepts-oral-exam-questions)
   - [Virtual Machines vs Docker](#virtual-machines-vs-docker)
   - [Linux Namespaces and Cgroups](#linux-namespaces-and-cgroups)
   - [PID 1, Daemons & Process Lifecycle (No Hacky Patches)](#pid-1-daemons--process-lifecycle-no-hacky-patches)
   - [Docker Networks: Bridge vs Host](#docker-networks-bridge-vs-host)
   - [Docker Volumes vs Bind Mounts](#docker-volumes-vs-bind-mounts)
   - [Secrets vs Environment Variables](#secrets-vs-environment-variables)
   - [TLSv1.2 & TLSv1.3 Protocols & FastCGI](#tlsv12--tlsv13-protocols--fastcgi)
3. [Line-by-Line Code Breakdown](#3-line-by-line-code-breakdown)
   - [Root Makefile](#root-makefile)
   - [srcs/docker-compose.yml](#srcsdocker-composeyml)
   - [srcs/.env & secrets/](#srcsenv--secrets)
   - [MariaDB Service (Alpine 3.23)](#mariadb-service-alpine-323)
   - [WordPress + PHP-FPM Service (Alpine 3.23 & PHP 8.3)](#wordpress--php-fpm-service-alpine-323--php-83)
   - [NGINX Service (Alpine 3.23 & TLS)](#nginx-service-alpine-323--tls)
4. [The Evaluation Day Playbook (Step-by-Step Live Demo)](#4-the-evaluation-day-playbook-step-by-step-live-demo)
5. [Evaluator Q&A Flashcards (Top 25 Defense Questions)](#5-evaluator-qa-flashcards-top-25-defense-questions)
6. [Live Code Modification Preparation (Chapter IX Defense Challenge)](#6-live-code-modification-preparation-chapter-ix-defense-challenge)

---

# 1. The Big Picture: Mental Model & Architecture

### What is Inception?
Inception requires you to build a production-like microservice web infrastructure inside a Linux Virtual Machine using Docker. 

Instead of downloading pre-made images from Docker Hub (like `docker pull wordpress`), you write your own custom `Dockerfile` for each service, base them on the **penultimate stable version of Alpine Linux (v3.23)**, orchestrate them with `docker-compose.yml`, and manage the lifecycle with a root `Makefile`.

### Architectural Overview

```
                      +------------------------------------------+
                      |         Host Machine / Browser           |
                      |   Domain: https://csamaha.42.fr:443      |
                      +--------------------+---------------------+
                                           |
                              Port 443 only| (TLSv1.2 / TLSv1.3)
                                           v
+ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
' Custom Docker Network: inception_net (Internal DNS: 127.0.0.11)             '
'                                                                             '
'   +---------------------------------------------------------------------+   '
'   | [Container: nginx] (Alpine 3.23)                                    |   '
'   | - Entrypoint: /usr/local/bin/entrypoint.sh (Generates TLS cert)     |   '
'   | - PID 1: nginx -g "daemon off;"                                     |   '
'   | - Serves static files directly from /var/www/html (read-only volume)|   '
'   | - Forwards *.php via FastCGI to wordpress:9000                      |   '
'   +----------------------------------+----------------------------------+   '
'                                      |                                      '
'                         FastCGI:9000 | (Private container-to-container)     '
'                                      v                                      '
'   +---------------------------------------------------------------------+   '
'   | [Container: wordpress] (Alpine 3.23)                                |   '
'   | - Entrypoint: /usr/local/bin/setup.sh                               |   '
'   | - PID 1: php-fpm83 -F                                               |   '
'   | - Downloads & configures WP Core via WP-CLI                         |   '
'   | - Creates Admin (csamaha_master) & Subscriber (wpuser)              |   '
'   +----------------------------------+----------------------------------+   '
'                                      |                                      '
'                            TCP: 3306 | (Private container-to-container)     '
'                                      v                                      '
'   +---------------------------------------------------------------------+   '
'   | [Container: mariadb] (Alpine 3.23)                                  |   '
'   | - Entrypoint: /usr/local/bin/entrypoint.sh                          |   '
'   | - PID 1: mariadbd --console                                         |   '
'   | - Initializes database 'wordpress' and user 'wp_user'               |   '
'   +----------------------------------+----------------------------------+   '
+ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
                                       |
                   +-------------------+-------------------+
                   |                                       |
                   v                                       v
         [Named Volume: wp_data]                 [Named Volume: db_data]
      Local driver (type: none, bind)         Local driver (type: none, bind)
                   |                                       |
                   v                                       v
        /home/csamaha/data/wp                   /home/csamaha/data/db
       (Website PHP files & assets)            (Physical MariaDB tables)
```

### The Life of an HTTP Request
1. You open `https://csamaha.42.fr` in your browser.
2. The browser consults `/etc/hosts`, which resolves `csamaha.42.fr` to `127.0.0.1` (localhost).
3. The request hits host port **443**. Docker routes port 443 to the **NGINX container**.
4. NGINX negotiates a TLS handshake (strictly TLSv1.2 or TLSv1.3) using its self-signed certificate (`csamaha.crt`).
5. **Static File Request** (e.g. `image.png`, `style.css`): NGINX serves it directly from the local volume mount `/var/www/html`.
6. **Dynamic Request** (e.g. `index.php`, `/wp-admin`):
   - NGINX matches `location ~ \.php$`.
   - It packages the request using the **FastCGI** binary protocol and forwards it to `wordpress:9000` through the internal bridge network `inception_net`.
   - The WordPress container's PHP-FPM process executes the PHP script.
   - When PHP needs data (e.g. posts, user authentication), it queries MariaDB at `mariadb:3306`.
   - MariaDB reads/writes data to `/var/lib/mysql` (mapped to `/home/csamaha/data/db`).
   - PHP-FPM generates the HTML and sends it back to NGINX via FastCGI.
   - NGINX encrypts the HTML response and transmits it over TLS to your browser.

---

# 2. Core Theoretical Concepts (Oral Exam Questions)

You will be asked theoretical questions during your defense. Memorize the explanations below.

---

### Virtual Machines vs Docker

```
+---------------------------------+      +---------------------------------+
|   Virtual Machine (Hypervisor)  |      |        Docker Container         |
+---------------------------------+      +---------------------------------+
|   App 1   |   App 2   |  App 3  |      |   App 1   |   App 2   |  App 3  |
| Libraries | Libraries |Libraries|      | Libraries | Libraries |Libraries|
|  Guest OS |  Guest OS | Guest OS|      +-----------+-----------+---------+
+-----------+-----------+---------+      |          Docker Engine          |
|           Hypervisor            |      +---------------------------------+
+---------------------------------+      |       Shared Host OS Kernel     |
|      Host Operating System      |      +---------------------------------+
+---------------------------------+      |          Physical Hardware      |
|        Physical Hardware        |      +---------------------------------+
+---------------------------------+
```

- **Architecture**:
  - **VMs**: Use a **Hypervisor** (Type 1 like ESXi/KVM, or Type 2 like VirtualBox) to emulate virtual hardware (virtual CPU, RAM, disk, NIC). Inside each VM runs a completely independent **Guest Operating System** with its own kernel.
  - **Docker**: Runs containers as native processes directly on the **shared Host Linux Kernel**. There is no guest kernel and no hardware emulation.
- **Resource Efficiency**:
  - VMs reserve fixed slices of CPU and RAM, boot slow background daemons, and consume gigabytes of storage per VM.
  - Containers only allocate memory and CPU dynamically on demand; an idle container uses almost zero overhead.
- **Startup Speed**: VMs take 30-90 seconds to boot the OS kernel; Docker containers start in milliseconds (just running the process).
- **Isolation**: VMs have hardware-level hypervisor boundaries (stronger isolation). Containers use process-level kernel primitives (Namespaces & Cgroups).

---

### Linux Namespaces and Cgroups

Containers are not real physical things; a container is simply an ordinary Linux process restricted by two Linux kernel features:

1. **Namespaces (What the process can SEE)**:
   Namespaces partition kernel resources so a process thinks it is running on its own dedicated system:
   - `PID` namespace: Process isolation. The container’s main process sees itself as **PID 1**, while on the host it has an ordinary PID (e.g., PID 28412).
   - `NET` namespace: Network virtualization. Provides independent virtual network interfaces (`eth0`), loopback (`lo`), routing tables, and private IP addresses.
   - `MNT` namespace: Mount point isolation. The container has its own root filesystem (`/`) decoupled from the host.
   - `IPC` namespace: Inter-Process Communication isolation (shared memory, semaphores).
   - `UTS` namespace: Hostname and domain isolation (container has its own hostname).
   - `USER` namespace: UID/GID mapping (a user can be UID 0 root inside the container, but map to an unprivileged UID on the host).

2. **Control Groups / Cgroups (What the process can USE)**:
   - Cgroups meter, throttle, and limit hardware resource consumption:
     - Memory limits (e.g., maximum 512MB RAM before OOM-killer fires).
     - CPU shares/quotas (preventing one container from starving the host CPU).
     - Disk I/O throttling and network bandwidth limits.

---

### PID 1, Daemons & Process Lifecycle (No Hacky Patches)

The subject strictly states:
> *"Prohibited hacky patches: `tail -f`, `bash`, `sleep infinity`, `while true`... Read about PID 1 and best practices."*

#### Why does PID 1 matter in Docker?
1. **Container Lifecycle is bound to PID 1**:
   A Docker container stays alive **only as long as its PID 1 process is alive**. If PID 1 terminates, the container immediately stops.
2. **Signal Handling (`SIGTERM`, `SIGINT`)**:
   When you run `docker stop`, Docker sends `SIGTERM` to **PID 1**.
   - If PID 1 is a proper application (like `nginx` or `mariadbd`), it initiates a graceful shutdown (closing sockets, saving buffers to disk).
   - If PID 1 is a dumb shell script or `tail -f`, it ignores `SIGTERM`. Docker waits 10 seconds, gives up, and forcefully kills the container with `SIGKILL` (`kill -9`), which can corrupt databases!
3. **Zombie Process Reaping**:
   In Unix, when a child process dies, it becomes a "zombie" until its parent calls `wait()`. If the parent dies first, the child is orphaned and adopted by PID 1. PID 1 has the system responsibility of reaping dead orphan processes.

#### Why do we use `exec` in entrypoint scripts?
Look at the end of our entrypoint scripts:
```bash
exec mariadbd --user=mysql --datadir=/var/lib/mysql --console
exec php-fpm83 -F
exec nginx -g "daemon off;"
```
- Without `exec`: The shell script runs as PID 1, spawns the daemon as PID 2, and either exits (killing the container) or hangs with a hacky loop.
- With `exec`: The Linux kernel **replaces the shell process with the target executable** while keeping the **same PID (PID 1)**! The shell completely disappears from memory.

#### Why do daemons run in the foreground?
By default, traditional Unix daemons "daemonize" (fork into the background and detach from stdin/stdout). If NGINX did this, the initial process would exit immediately, causing Docker to think the application finished and terminate the container!
- `nginx -g "daemon off;"`: Forces NGINX to stay in the foreground.
- `php-fpm83 -F`: The `-F` flag forces PHP-FPM to run in the foreground.
- `mariadbd --console`: Directs logging to stdout/stderr and runs in the foreground.

---

### Docker Networks: Bridge vs Host

- **User-Defined Bridge Network (`inception_net`)**:
  - Creates an isolated software bridge interface on the host kernel.
  - Every container connected to the bridge receives a private IP address (e.g. `172.19.0.2`).
  - **Embedded DNS Resolver**: Docker runs an internal DNS server at `127.0.0.11`. If WordPress queries `mariadb`, Docker DNS translates `mariadb` directly to its internal IP address.
  - Containers can communicate on all internal ports (`3306`, `9000`), but none of these ports are accessible from the host or external internet unless explicitly published (`ports:`).
- **Host Network (`network: host`)**:
  - Removes all network isolation between container and host. The container shares the host's network interfaces directly.
  - Security risk: Ports bound inside the container bind directly on the host interface.
  - **Strictly forbidden by the Inception subject**.

---

### Docker Volumes vs Bind Mounts

The subject states:
> *"You must use Docker named volumes for these two persistent storages. Bind mounts are not allowed for these volumes. Both named volumes must store their data inside `/home/login/data`."*

```
Direct Bind Mount (FORBIDDEN by subject):
services:
  mariadb:
    volumes:
      - /home/csamaha/data/db:/var/lib/mysql   <-- Direct host bind path (Bypasses Docker Volume API)

Docker Named Volume with Local Driver (REQUIRED by subject):
volumes:
  db_data:                                    <-- Named volume registered in Docker
    driver: local
    driver_opts:
      type: none                              <-- Linux bind mount filesystem type
      o: bind                                 <-- Mount option: bind
      device: /home/csamaha/data/db           <-- Stored in /home/login/data
```

- **Standard Bind Mount**: Directly attaches an arbitrary host file/directory into a container. Docker does not manage its lifecycle, it does not show up in `docker volume ls`, and it breaks container portability.
- **Docker Named Volume**: Managed by the Docker engine daemon (`docker volume create`, `docker volume ls`, `docker volume inspect`, `docker volume rm`). By using `driver: local` with `driver_opts: { type: none, o: bind, device: ... }`, we create a legitimate named Docker volume that stores its underlying data at the exact host directory demanded by the subject (`/home/csamaha/data/`).

---

### Secrets vs Environment Variables

- **Environment Variables (`.env`)**:
  - Environment variables are stored in the container's process descriptor.
  - Anyone running `docker inspect <container_id>` or `cat /proc/1/environ` can read all passwords in plaintext.
  - Child processes inherit environment variables, meaning any script or third-party plugin running inside the container can steal database credentials.
  - Subject requires `.env` for non-sensitive configuration (`DOMAIN_NAME`, `MYSQL_USER`, `MYSQL_DATABASE`, `PORT`).
- **Docker Secrets**:
  - Secrets are stored outside the images and containers.
  - In Docker Compose, secrets are mounted into the container as files on a **RAM-backed temporary filesystem (`tmpfs`)** at `/run/secrets/<secret_name>`.
  - Secrets are **never written to disk** inside the container and are **never exposed in `docker inspect`**.
  - A process must explicitly read the file (`cat /run/secrets/db_password`) to access the password.

---

### TLSv1.2 & TLSv1.3 Protocols & FastCGI

- **TLS (Transport Layer Security)**:
  - Cryptographic protocol providing privacy (symmetric encryption like AES-GCM or ChaCha20) and integrity (HMAC or Poly1305) over the internet.
  - **TLSv1.0 and TLSv1.1** are deprecated and insecure (vulnerable to POODLE, BEAST, and SWEET32 attacks).
  - **TLSv1.2**: Established modern standard; 2-RTT (Round Trip Time) handshake.
  - **TLSv1.3**: Latest standard; speeds up handshake to 1-RTT (or 0-RTT resumption), drops obsolete insecure ciphers, and encrypts the handshake certificates.
  - The subject mandates: **TLSv1.2 or TLSv1.3 only**.
- **FastCGI & PHP-FPM**:
  - NGINX is an HTTP web server optimized for high-concurrency static files and reverse proxying; it does **not** have an embedded PHP interpreter.
  - **PHP-FPM (FastCGI Process Manager)** is a standalone daemon that manages a pool of worker processes waiting to interpret PHP code.
  - **FastCGI** is a binary protocol that allows the web server (NGINX) to send HTTP request environment variables, headers, and script filenames over a TCP socket (`wordpress:9000`) to PHP-FPM and receive the processed HTML response.

---

# 3. Line-by-Line Code Breakdown

Let's dissect every file in the project so you can answer any line-specific question.

---

### Root Makefile
[View Makefile](file:///home/csamaha/Desktop/Inception-main/Makefile)

```makefile
SRC_DIR        := srcs
COMPOSE_FILE   := docker-compose.yml
ENV_FILE       := $(SRC_DIR)/.env
SECRETS_DIR    := secrets

COMPOSE_CMD    := $(shell command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && echo "docker compose" || echo "docker-compose")
```
- Detects whether modern Docker Compose v2 (`docker compose`) or legacy v1 (`docker-compose`) is installed.

```makefile
PROJECT_NAME   := $(shell sed -n 's/^COMPOSE_PROJECT_NAME=\(.*\)/\1/p' $(ENV_FILE) 2>/dev/null | tr -d '\r"')
DOMAIN_NAME    := $(shell sed -n 's/^DOMAIN_NAME=\(.*\)/\1/p'            $(ENV_FILE) 2>/dev/null | tr -d '\r"')
HOST_DB_PATH   := $(shell sed -n 's/^HOST_DB_PATH=\(.*\)/\1/p'            $(ENV_FILE) 2>/dev/null | tr -d '\r"')
HOST_WP_PATH   := $(shell sed -n 's/^HOST_WP_PATH=\(.*\)/\1/p'            $(ENV_FILE) 2>/dev/null | tr -d '\r"')
```
- Extracts configuration variables directly from `srcs/.env`. Uses `tr -d '\r"'` to strip Windows carriage returns and quotes.

```makefile
define ensure_env
    @ if [ ! -f "$(ENV_FILE)" ]; then echo "[ERROR] .env missing"; exit 1; fi
endef
define ensure_dirs
    @ mkdir -p "$(HOST_DB_PATH)" "$(HOST_WP_PATH)"
endef
define ensure_secrets
    @ for f in db_password.txt db_root_password.txt wp_admin_password.txt wp_user_password.txt ; do \
        if [ ! -f "$(SECRETS_DIR)/$$f" ]; then echo "[ERROR] Missing secret file: $$f"; exit 1; fi ; \
      done
endef
```
- Defensive checks: Ensures the environment file, required host directories (`/home/csamaha/data/...`), and plain-text secrets exist before running Docker Compose.

```makefile
all: up
up: ## Build and start services (detached)
    $(call ensure_env)
    $(call ensure_dirs)
    $(call ensure_secrets)
    $(call compose, up -d --build)
```
- Running `make` triggers `all`, which invokes `up`. Builds images if necessary and starts all containers in the background (`-d`).

```makefile
fclean: clean
    rm -rf "$(HOST_DB_PATH)" "$(HOST_WP_PATH)" 2>/dev/null || sudo rm -rf "$(HOST_DB_PATH)" "$(HOST_WP_PATH)"
    docker volume rm -f $(PROJECT_NAME)_db_data $(PROJECT_NAME)_wp_data 2>/dev/null || true
    docker system prune -af --volumes 2>/dev/null || true
```
- Full cleanup: Stops containers, deletes the host data directories (`/home/csamaha/data`), removes Docker named volumes, and purges unused Docker images and build caches.

---

### srcs/docker-compose.yml
[View docker-compose.yml](file:///home/csamaha/Desktop/Inception-main/srcs/docker-compose.yml)

```yaml
secrets:
  db_password:
    file: ../secrets/db_password.txt
  db_root_password:
    file: ../secrets/db_root_password.txt
  wp_admin_password:
    file: ../secrets/wp_admin_password.txt
  wp_user_password:
    file: ../secrets/wp_user_password.txt
```
- Registers secrets from the root `./secrets` directory. Mounted automatically to `/run/secrets/<name>` inside containers.

```yaml
volumes:
  db_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${HOST_DB_PATH}
  wp_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${HOST_WP_PATH}
```
- Defines the two persistent named volumes using Docker's `local` driver, mapped to `/home/csamaha/data/db` and `/home/csamaha/data/wp`.

```yaml
services:
  mariadb:
    container_name: mariadb
    image: mariadb
    build:
      context: ./requirements/mariadb
      dockerfile: Dockerfile
    restart: always
    env_file:
      - .env
    secrets:
      - db_password
      - db_root_password
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - inception
```
- Service name matches image name (`image: mariadb`).
- Built from local Dockerfile; no pre-pulled image.
- `restart: always`: Container restarts automatically if it crashes or the Docker daemon reboots.
- Only connected to internal `inception` bridge network. Port 3306 is **not** exposed to the host.

```yaml
  wordpress:
    container_name: wordpress
    image: wordpress
    build:
      context: ./requirements/wordpress
      dockerfile: Dockerfile
    restart: always
    depends_on:
      - mariadb
    secrets:
      - db_password
      - wp_admin_password
      - wp_user_password
    volumes:
      - wp_data:/var/www/html
    networks:
      - inception
```
- Mounts `wp_data` to `/var/www/html`. Port 9000 is internal only.

```yaml
  nginx:
    container_name: nginx
    image: nginx
    build:
      context: ./requirements/nginx
      dockerfile: Dockerfile
    restart: always
    depends_on:
      - wordpress
    ports:
      - "443:443"
    volumes:
      - wp_data:/var/www/html:ro
    networks:
      - inception
```
- **The only service publishing a port on the host**: `"443:443"`.
- Mounts `wp_data` with `:ro` (read-only), so NGINX can serve static files but cannot modify them.

---

### srcs/.env & secrets/
[View .env](file:///home/csamaha/Desktop/Inception-main/srcs/.env)

- `DOMAIN_NAME=csamaha.42.fr`
- `HOST_DB_PATH=/home/csamaha/data/db`
- `HOST_WP_PATH=/home/csamaha/data/wp`
- `WP_ADMIN_USER=csamaha_master`: Does **not** contain `admin` or `Admin` or `administrator` (satisfies 42 rule).
- `WP_USER=wpuser`: Second user required by the subject with non-admin (subscriber) role.
- `MYSQL_PASSWORD_FILE=/run/secrets/db_password`: In-memory file path inside container.

---

### MariaDB Service (Alpine 3.23)
[View MariaDB Dockerfile](file:///home/csamaha/Desktop/Inception-main/srcs/requirements/mariadb/Dockerfile)

- **Dockerfile**:
  - `FROM alpine:3.23`: Penultimate stable Alpine release.
  - `RUN apk add --no-cache mariadb mariadb-client bash`: Installs database engine.
  - `USER mysql`: Runs as unprivileged system user.
  - `ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]`
- **conf/my.cnf**:
  - `bind-address=0.0.0.0`: Listens on all container interfaces so WordPress can reach it.
  - `port=3306`: Default MySQL/MariaDB port.
  - `skip-name-resolve`: Disables DNS reverse lookup on incoming client connections for faster speed.
- **tools/entrypoint.sh**:
  - Reads passwords safely: `DB_PASS="$(tr -d '\r\n' < "${DB_PASS_FILE}")"`.
  - Checks if `/var/lib/mysql/mysql` exists. If not, runs `mariadb-install-db` to initialize the data directory.
  - Starts a temporary bootstrap server:
    ```sql
    ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PASS}';
    CREATE DATABASE IF NOT EXISTS `wordpress`;
    CREATE USER IF NOT EXISTS 'wp_user'@'%' IDENTIFIED BY '${DB_PASS}';
    GRANT ALL PRIVILEGES ON `wordpress`.* TO 'wp_user'@'%';
    FLUSH PRIVILEGES;
    ```
  - Finishes with: `exec mariadbd --user=mysql --datadir=/var/lib/mysql --console` (MariaDB runs as PID 1).

---

### WordPress + PHP-FPM Service (Alpine 3.23 & PHP 8.3)
[View WordPress Dockerfile](file:///home/csamaha/Desktop/Inception-main/srcs/requirements/wordpress/Dockerfile)

- **Dockerfile**:
  - `FROM alpine:3.23`
  - Installs PHP 8.3 modules (`php83`, `php83-fpm`, `php83-mysqli`, `php83-opcache`, `php83-curl`, `php83-gd`, `php83-mbstring`, `php83-phar`).
  - Downloads official **WP-CLI** executable (`/usr/local/bin/wp`).
  - Creates unprivileged `www-data` user and assigns permissions.
  - Copies pool config to `/etc/php83/php-fpm.d/www.conf`.
  - `ENTRYPOINT ["/usr/local/bin/setup.sh"]`
- **conf/www.conf**:
  - `listen = 0.0.0.0:9000`: Listens on TCP port 9000 for NGINX FastCGI requests.
  - `user = www-data`, `group = www-data`.
  - `clear_env = no`: Allows PHP processes to access container environment variables.
- **tools/setup.sh**:
  - Validates: `if [[ "${WP_ADMIN_USER}" =~ [aA][dD][mM][iI][nN] ]]; then exit 1; fi`.
  - Retries connecting to MariaDB: `mariadb -h "${MYSQL_HOST}" -u "${MYSQL_USER}" ...` (waits for database readiness without crashing).
  - Downloads WordPress core files if missing.
  - Generates `wp-config.php` dynamically.
  - Runs `wp core install` to provision database tables, site title, and administrator account.
  - Runs `wp user create` to create the second subscriber user.
  - Re-applies permissions: `chown -R www-data:www-data /var/www/html`.
  - Finishes with: `exec php-fpm83 -F` (PHP-FPM runs in foreground as PID 1).

---

### NGINX Service (Alpine 3.23 & TLS)
[View NGINX Dockerfile](file:///home/csamaha/Desktop/Inception-main/srcs/requirements/nginx/Dockerfile)

- **Dockerfile**:
  - `FROM alpine:3.23`
  - Installs `nginx`, `openssl`, `bash`.
  - `EXPOSE 443`
  - `ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]`
- **conf/nginx.conf**:
  - `ssl_protocols TLSv1.2 TLSv1.3;`: Disables SSLv3, TLS 1.0, and TLS 1.1.
  - `ssl_prefer_server_ciphers on;`
  - `listen 443 ssl;`
  - `server_name csamaha.42.fr;`
  - `location ~ \.php$`:
    ```nginx
    include        fastcgi_params;
    fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_pass   wordpress:9000;
    ```
- **tools/entrypoint.sh**:
  - Generates a self-signed certificate using OpenSSL if not already present:
    `openssl req -x509 -nodes -newkey rsa:2048 -days 365 -keyout csamaha.key -out csamaha.crt -subj "/CN=csamaha.42.fr"`.
  - Finishes with: `exec nginx -g "daemon off;"` (NGINX runs in foreground as PID 1).

---

# 4. The Evaluation Day Playbook (Step-by-Step Live Demo)

Follow this exact script in front of your evaluator.

### Phase 1: Verify Repository and Clean Start
```bash
# 1. Show git status / branch (must be clean, no passwords committed)
git status

# 2. Show directory structure matches subject requirements
ls -la
ls -la srcs/
ls -la secrets/

# 3. Clean everything and build from scratch
make fclean
make
```

### Phase 2: Verify Images and Alpine 3.23
```bash
# 1. Verify images have the same names as services (mariadb, wordpress, nginx)
# and verify NO ':latest' tag is used
docker images

# 2. Verify all images are built on Alpine 3.23
docker inspect mariadb | grep -i 'alpine'
docker inspect wordpress | grep -i 'alpine'
docker inspect nginx | grep -i 'alpine'

# 3. Or run cat /etc/os-release inside each container:
docker exec -it mariadb cat /etc/os-release
docker exec -it wordpress cat /etc/os-release
docker exec -it nginx cat /etc/os-release
```
*Expected output: `VERSION_ID=3.23.x` and `PRETTY_NAME="Alpine Linux v3.23"`.*

### Phase 3: Verify Process Management (PID 1 & No Hacky Loops)
```bash
# Show running processes inside each container:
docker exec -it mariadb ps aux
# -> PID 1 must be 'mariadbd'

docker exec -it wordpress ps aux
# -> PID 1 must be 'php-fpm83'

docker exec -it nginx ps aux
# -> PID 1 must be 'nginx: master process'
```
*Point out to the evaluator that there are no `tail -f`, `sleep infinity`, or `bash` wrapper scripts running.*

### Phase 4: Verify Ports and Network Isolation
```bash
# 1. Check published ports on host:
docker ps
# ONLY NGINX should have "0.0.0.0:443->443/tcp".
# MariaDB (3306) and WordPress (9000) must NOT show published host ports!

# 2. Verify network bridge name:
docker network ls
# Shows 'inception_net'
```

### Phase 5: Test TLS Protocols via Terminal
```bash
# Test TLSv1.2 (Should SUCCEED with HTTP 200 or 301/302)
curl -kv --tlsv1.2 --tls-max 1.2 https://csamaha.42.fr

# Test TLSv1.3 (Should SUCCEED)
curl -kv --tlsv1.3 --tls-max 1.3 https://csamaha.42.fr

# Test TLSv1.1 (MUST FAIL because TLSv1.1 is forbidden)
curl -kv --tlsv1.1 --tls-max 1.1 https://csamaha.42.fr
```

### Phase 6: Web Browser & WordPress Users Verification
1. Open browser to `https://csamaha.42.fr`. Show the WordPress site loads over HTTPS.
2. Go to `https://csamaha.42.fr/wp-admin`.
3. Log in with:
   - Username: `csamaha_master`
   - Password: `cat secrets/wp_admin_password.txt`
4. Navigate to **Users** in the dashboard:
   - Point out that there are **two users**:
     1. `csamaha_master` (Administrator) — highlight that the username **does not contain 'admin' or 'administrator'**.
     2. `wpuser` (Subscriber).

### Phase 7: Prove Data Persistence Across Teardown
1. While logged in as admin, create a new post titled *"Evaluation Test Post"* and publish it.
2. Leave a comment on the post.
3. Switch to terminal and completely destroy the containers:
   ```bash
   make down
   # Verify containers are destroyed
   docker ps
   ```
4. Show the physical files intact on host:
   ```bash
   ls -la /home/csamaha/data/db
   ls -la /home/csamaha/data/wp
   ```
5. Restart the stack:
   ```bash
   make up
   ```
6. Refresh the browser at `https://csamaha.42.fr`:
   - The *"Evaluation Test Post"* and comment are still there!
   - This proves persistent storage is 100% working.

### Phase 8: Prove Crash Resiliency (`restart: always`)
```bash
# Kill a container with SIGKILL:
docker kill nginx

# Immediately check status:
docker ps
# You will see NGINX was restarted seconds ago (Up 2 seconds)!
```

---

# 5. Evaluator Q&A Flashcards (Top 25 Defense Questions)

Here are direct answers to the toughest questions evaluators love to ask.

#### Q1: Why did you choose Alpine 3.23?
> **Answer**: The subject requires using either the penultimate stable version of Alpine or Debian. As Alpine 3.24 is the latest release, Alpine 3.23 is the penultimate stable release. Alpine was chosen because it is lightweight (~7MB base image), security-oriented (uses musl libc and busybox), has a minimal attack surface, and builds significantly faster than Debian.

#### Q2: Why is the NGINX container the only one exposing a port?
> **Answer**: Following the principle of least privilege and defense-in-depth, only the reverse proxy needs external connectivity to terminate TLS. WordPress (PHP-FPM) and MariaDB only need to communicate privately with each other inside the internal Docker bridge network (`inception_net`). Exposing database port 3306 or FastCGI port 9000 to the host would introduce unnecessary attack vectors.

#### Q3: How do the containers find each other if their IP addresses change?
> **Answer**: Docker has an embedded DNS server at `127.0.0.11` for user-defined bridge networks. When WordPress requests the host `mariadb`, Docker's DNS server automatically resolves the service name `mariadb` to its current container IP.

#### Q4: Why is `network: host` forbidden in this project?
> **Answer**: `network: host` removes all network isolation between the container and the host. The container shares the host's network interfaces directly, allowing container processes to bind host ports, sniff host traffic, and bypass the container network perimeter.

#### Q5: What is the difference between a CMD and an ENTRYPOINT in a Dockerfile?
> **Answer**: `ENTRYPOINT` specifies the executable that is always invoked when the container starts. `CMD` specifies default arguments passed to that entrypoint, which can be overridden when running `docker run <image> [args]`. In our Dockerfiles, we use `ENTRYPOINT` with our setup scripts so initialization always runs.

#### Q6: What does `exec` do in your entrypoint scripts?
> **Answer**: In Unix, `exec` executes a command by replacing the current process image in memory with the new process, retaining the exact same Process ID (PID). By executing `exec nginx -g "daemon off;"`, the shell script terminates and NGINX becomes PID 1. This allows NGINX to receive Unix signals directly and cleanly shut down.

#### Q7: Why are hacky patches like `tail -f /dev/null` or `sleep infinity` forbidden?
> **Answer**: These tricks are used by novices to keep a container alive when their main service forks into the background. However, they cause `tail` or `sleep` to become PID 1. When Docker stops the container, `tail` ignores `SIGTERM`, forcing Docker to forcefully kill the container after 10 seconds (`SIGKILL`), risking data loss and corrupting database transactions.

#### Q8: Where does Docker store named volumes by default vs your project?
> **Answer**: By default, Docker stores named volumes under `/var/lib/docker/volumes/<volume_name>/_data`. However, the subject explicitly mandates storing persistent data in `/home/login/data`. We configured the `local` driver with `driver_opts: { type: none, o: bind, device: /home/csamaha/data/... }`, creating a Docker-managed named volume whose backing storage is located at `/home/csamaha/data`.

#### Q9: Why did the subject say "Bind mounts are not allowed for these volumes"?
> **Answer**: The subject forbids using raw anonymous host bind mounts defined directly on services (e.g. `volumes: - /home/...:/var/...`) because they bypass Docker's volume management subsystem. Instead, the subject requires named volume definitions under the top-level `volumes:` key.

#### Q10: Why are environment variables unsafe for passwords?
> **Answer**: Environment variables can be read by anyone with Docker access via `docker inspect` or `docker compose config`. They are also exposed on the host through `/proc/<pid>/environ`, leaked in crash reports, and inherited by all child processes inside the container. Docker Secrets, on the other hand, are mounted into RAM-only temporary files (`/run/secrets/`) and are never exposed via inspect commands.

#### Q11: How does NGINX communicate with WordPress?
> **Answer**: Over FastCGI. NGINX receives the HTTPS request from the browser, terminates the TLS session, matches `.php` files via regex, and proxies the request to `wordpress:9000` via FastCGI using TCP. PHP-FPM executes the PHP script and returns the generated content back to NGINX.

#### Q12: Why is port 80 not open?
> **Answer**: The subject explicitly requires: *"Your NGINX container must be the only entrypoint into your infrastructure via the port 443 only, using the TLSv1.2 or TLSv1.3 protocol."* Plain HTTP over port 80 transmits data unencrypted in cleartext and is strictly disallowed.

#### Q13: Why did you create two users in WordPress?
> **Answer**: The subject requires: *"In your WordPress database, there must be two users, one of them being the administrator. The administrator’s username can’t contain admin/Admin or administrator/Administrator."* We created `csamaha_master` with the `administrator` role and `wpuser` with the `subscriber` role.

#### Q14: How does MariaDB know not to re-initialize the database on subsequent starts?
> **Answer**: In `entrypoint.sh`, we check if the directory `/var/lib/mysql/mysql` exists. If it exists, the database was already provisioned in the persistent volume, so the script skips bootstrapping and boots MariaDB immediately.

#### Q15: What is the purpose of `.dockerignore`?
> **Answer**: When Docker builds an image, it sends the entire build directory (the "build context") to the Docker daemon. `.dockerignore` prevents unnecessary files, sensitive secrets, `.env`, `.git`, and documentation from being sent to the daemon or accidentally baked into the container image.

#### Q16: How does `restart: always` work?
> **Answer**: The Docker daemon monitors container process exit codes. If the container process dies (whether due to a crash with a non-zero exit code or being killed with `docker kill`), the Docker daemon automatically spins up a new instance of that container. It also starts the container automatically when the Docker service starts on host boot.

#### Q17: What is the difference between TLSv1.2 and TLSv1.3?
> **Answer**: TLSv1.3 simplifies the cryptographic handshake (1 Round Trip Time instead of 2 RTT), eliminates legacy and insecure cipher suites (like RC4, DES, 3DES, MD5, SHA-1, and RSA key exchange), mandates forward secrecy (Ephemeral Diffie-Hellman), and encrypts more of the handshake packet headers.

#### Q18: Why does NGINX mount the WordPress volume as `:ro`?
> **Answer**: In `docker-compose.yml`, the WordPress volume is mounted into NGINX with `wp_data:/var/www/html:ro`. `:ro` stands for Read-Only. NGINX only needs to read static files (images, CSS, JS) to serve them to clients. It should never have write access to website files, preventing a compromised web server from writing malicious files to the website.

#### Q19: What does `wp core is-installed` do in your setup script?
> **Answer**: It is a WP-CLI command that queries the database to check if WordPress database tables already exist. This ensures our setup script is **idempotent**—it installs WordPress only on the first boot, and updates site URLs and users on subsequent restarts without throwing errors or overwriting existing data.

#### Q20: What is a self-signed certificate and why is it used here?
> **Answer**: A certificate whose public key identity is signed by its own private key rather than a trusted Certificate Authority (like Let's Encrypt or DigiCert). Because `.42.fr` is an internal private domain mapped locally to `127.0.0.1`, commercial CAs cannot validate domain ownership. OpenSSL generates a self-signed X.509 certificate for local encryption.

#### Q21: What is the difference between `docker compose down` and `docker compose down -v`?
> **Answer**: `docker compose down` stops and removes containers and networks, but **keeps named volumes intact**. Adding the `-v` flag deletes all named volumes declared in the Compose file, wiping out persistent database and website files.

#### Q22: How does MariaDB handle root password authentication securely?
> **Answer**: During initial bootstrap, `mariadbd --bootstrap` executes an `ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PASS}';` query. The password is read from the Docker secret file in tmpfs memory (`/run/secrets/db_root_password`), never exposed in the process tree or Dockerfile.

#### Q23: Why do we have `clear_env = no` in `www.conf`?
> **Answer**: By default, PHP-FPM clears environment variables in worker processes for security in shared hosting environments. Setting `clear_env = no` allows PHP worker processes to read container environment variables like `DB_HOST`, `DB_NAME`, and `WP_URL`.

#### Q24: What happens during `make re`?
> **Answer**: `make re` calls `fclean` followed by `up`. `fclean` wipes containers, networks, images, named volumes, and host directories (`/home/csamaha/data`). `up` recreates host directories, validates secrets, rebuilds images from scratch, and brings up a brand-new pristine environment.

#### Q25: Why is there a `.gitignore` if secrets are in the project folder?
> **Answer**: The subject states that any credentials, API keys, or passwords found in your Git repository will result in project failure. `.gitignore` ensures that `secrets/*.txt` and `srcs/.env` cannot be accidentally staged or pushed to your remote Git repository during evaluation submission.

---

# 6. Live Code Modification Preparation (Chapter IX Defense Challenge)

Chapter IX warns that evaluators may ask you to make a minor modification to verify you understand your code. Here is how to handle the most common requests:

### Challenge 1: "Change the domain name or WordPress site title"
1. Edit `srcs/.env`:
   ```bash
   WP_TITLE="New Evaluation Title"
   DOMAIN_NAME=newdomain.42.fr
   ```
2. Update `/etc/hosts` if necessary:
   ```bash
   echo "127.0.0.1 newdomain.42.fr" | sudo tee -a /etc/hosts
   ```
3. Restart the stack:
   ```bash
   make restart
   ```

### Challenge 2: "Add a custom security header to NGINX"
1. Edit `srcs/requirements/nginx/conf/nginx.conf`.
2. Inside the `server { ... }` block, add:
   ```nginx
   add_header X-Frame-Options "SAMEORIGIN";
   add_header X-Content-Type-Options "nosniff";
   ```
3. Rebuild and restart:
   ```bash
   make up
   ```
4. Verify with curl:
   ```bash
   curl -I -k https://csamaha.42.fr
   # Look for 'X-Frame-Options: SAMEORIGIN' in headers!
   ```

### Challenge 3: "Change the subscriber user's role to editor"
1. In `srcs/requirements/wordpress/tools/setup.sh`:
   Find `--role=subscriber` and change it to `--role=editor`.
2. Restart WordPress container:
   ```bash
   make restart
   ```
3. Show in WordPress dashboard under **Users** that `wpuser` is now an Editor.

### Challenge 4: "Add a new environment variable to a container"
1. Add the variable to `srcs/.env`:
   ```env
   CUSTOM_VAR="hello_evaluator"
   ```
2. Add it under the service's `environment:` section in `srcs/docker-compose.yml`:
   ```yaml
   environment:
     - CUSTOM_VAR=${CUSTOM_VAR}
   ```
3. Restart and prove it is accessible inside the container:
   ```bash
   make up
   docker exec -it wordpress printenv CUSTOM_VAR
   # Outputs: hello_evaluator
   ```

---

### You are ready.
You now understand the architecture, the theory, the code, the live verification commands, and the defense questions. Good luck on your Inception defense!
