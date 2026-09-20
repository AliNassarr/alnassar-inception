*This project has been created as part of the 42 curriculum by alnassar.*

# Inception — Complete Project & Defense Guide

---

## Table of Contents
1. [Description & Overview](#description--overview)
2. [Architecture & Request Flow](#architecture--request-flow)
3. [Required Technical Comparisons](#required-technical-comparisons)
   - [Virtual Machines vs. Docker](#1-virtual-machines-vs-docker)
   - [Docker Secrets vs. Environment Variables](#2-docker-secrets-vs-environment-variables)
   - [Docker Network vs. Host Network](#3-docker-network-vs-host-network)
   - [Docker Volumes vs. Bind Mounts](#4-docker-volumes-vs-bind-mounts)
4. [Process Lifecycle & PID 1 Policy](#process-lifecycle--pid-1-policy)
5. [The Three Services Explained](#the-three-services-explained)
   - [NGINX](#1-nginx-the-front-door)
   - [WordPress + PHP-FPM](#2-wordpress--php-fpm-the-engine)
   - [MariaDB](#3-mariadb-the-database)
6. [Instructions & How to Run](#instructions--how-to-run)
7. [Evaluation Day Playbook (Commands & Defense)](#evaluation-day-playbook-commands--defense)
8. [Live Code Modification Guide (Changing a Port)](#live-code-modification-guide-changing-a-port)
9. [Automatic Fail Checklist (Instant 0 Traps)](#automatic-fail-checklist-instant-0-traps)
10. [Resources & AI Usage Statement](#resources--ai-usage-statement)

---

## Description & Overview

**Inception** is a system administration and DevOps project in the 42 curriculum. The goal is to build, configure, and orchestrate a secure multi-container web infrastructure from scratch using **Docker** and **Docker Compose**.

### Key Rules & Constraints:
- **No Pre-built Images**: Using ready-made images from DockerHub (like `FROM wordpress:latest` or `FROM nginx:latest`) is strictly forbidden. Every service must have its own custom `Dockerfile`.
- **Penultimate Stable OS**: All containers are built on **Alpine Linux v3.23** for minimal size, performance, and security.
- **Single Entry Point**: **NGINX** is the only container that exposes a port to the host machine, strictly over **Port 443** using **TLSv1.2 or TLSv1.3**.
- **Data Persistence**: WordPress files and database tables are permanently saved on the host machine at `/home/alnassar/data/wp` and `/home/alnassar/data/db` using Docker named volumes.
- **Strict Process Management**: No background daemons (`&`) or hacky loops (`tail -f /dev/null`, `sleep infinity`). Each container runs its primary daemon in the foreground as **PID 1**.

---

## Architecture & Request Flow

```
                      Client / Web Browser
                    [ https://alnassar.42.fr ]
                               │
               Host Port 443   │ (TLSv1.2 / TLSv1.3 only)
             (Port 80 closed)  ▼
┌──────────────────────────────────────────────────────────────┐
│  Docker Bridge Network: inception_net (Internal DNS 127.0.0.11)│
│                                                              │
│  ┌─────────────────┐                                         │
│  │      NGINX      │ (Alpine 3.23)                           │
│  │   (Port 443)    │ ── Serves static files directly         │
│  └────────┬────────┘                                         │
│           │ FastCGI:9000 (Private internal communication)    │
│           ▼                                                  │
│  ┌─────────────────┐                                         │
│  │    WordPress    │ (Alpine 3.23 + PHP-FPM 8.3)             │
│  │   (Port 9000)   │ ── Executes PHP scripts & WP-CLI        │
│  └────────┬────────┘                                         │
│           │ TCP:3306 (Private internal communication)        │
│           ▼                                                  │
│  ┌─────────────────┐                                         │
│  │     MariaDB     │ (Alpine 3.23)                           │
│  │   (Port 3306)   │ ── Relational database storage          │
│  └─────────────────┘                                         │
└──────────────────────────────────────────────────────────────┘
           │                                       │
           ▼                                       ▼
  [Volume: wp_data]                       [Volume: db_data]
  Host: /home/alnassar/data/wp            Host: /home/alnassar/data/db
```

### Request Lifecycle:
1. **User Request**: The user enters `https://alnassar.42.fr`. `/etc/hosts` maps this domain to `127.0.0.1`.
2. **TLS Termination**: NGINX receives the request on port 443, verifies the TLS 1.2/1.3 handshake with its SSL certificate, and inspects the URL.
3. **Static Content**: If the request is for an image, stylesheet, or script (`.css`, `.js`, `.png`), NGINX serves it directly from `/var/www/html` (mounted read-only).
4. **Dynamic Content**: If the request is for a PHP page (`index.php`, `/wp-admin`), NGINX translates it into a binary **FastCGI** request and passes it over the internal network to `wordpress:9000`.
5. **Processing & Database**: PHP-FPM runs the script. If data is needed (posts, user authentication), it queries MariaDB at `mariadb:3306`.
6. **Response**: MariaDB returns data $\rightarrow$ PHP-FPM builds the HTML $\rightarrow$ NGINX encrypts it $\rightarrow$ Browser renders the page.

---

## Required Technical Comparisons

### 1. Virtual Machines vs. Docker

| Feature | Virtual Machine (VM) | Docker Container |
| :--- | :--- | :--- |
| **Architecture** | Emulates physical hardware using a **Hypervisor** (e.g., VirtualBox, KVM). | Shares the **Host Linux Kernel** directly. No virtual hardware. |
| **Operating System** | Runs a complete, independent **Guest OS** with its own kernel. | Contains only application binaries and libraries. No guest OS kernel. |
| **Startup Time** | 30 to 60 seconds (boots full operating system). | Milliseconds (starts like a regular Linux process). |
| **Resource Usage** | Heavy (reserves several gigabytes of RAM and CPU upfront). | Extremely lightweight (shares host CPU and memory dynamically). |
| **Isolation Mechanism** | Hardware-level virtualization managed by the hypervisor. | Kernel-level isolation using **Namespaces** and **Cgroups**. |

> **Key Linux Kernel Primitives**:
> - **Namespaces** (Isolation & Visibility): Partition kernel resources so each container sees its own PID (process tree), NET (network interfaces/routing), MNT (filesystem mounts), IPC (inter-process communication), and UTS (hostname).
> - **Cgroups** (Control Groups / Resource Quotas): Measure and enforce limits on memory, CPU usage, disk I/O, and network bandwidth per container.

---

### 2. Docker Secrets vs. Environment Variables

| Feature | Environment Variables (`.env`) | Docker Secrets (`secrets/`) |
| :--- | :--- | :--- |
| **Storage Location** | Stored in the container process environment table (`/proc/<pid>/environ`). | Mounted in-memory on a temporary RAM filesystem (`tmpfs` at `/run/secrets/`). |
| **Visibility** | Easily inspected via `docker inspect` or `docker compose config`. | **Never** visible in `docker inspect` or image layers. |
| **Disk Exposure** | May leak into logs, core dumps, or child processes. | Never written to non-volatile disk inside the container. |
| **Use Case** | Non-sensitive configuration (e.g., `DOMAIN_NAME`, `MYSQL_USER`). | Confidential credentials (e.g., database passwords, admin passwords). |

---

### 3. Docker Network vs. Host Network

| Feature | User-Defined Bridge (`inception_net`) | Host Network (`network: host`) |
| :--- | :--- | :--- |
| **Isolation** | Completely isolated virtual software bridge inside the kernel. | Zero isolation; attaches containers directly to host network interfaces. |
| **DNS Resolution** | Built-in Docker DNS (`127.0.0.11`) resolves containers by **service name** (e.g., `mariadb`, `wordpress`). | No internal DNS. Containers must bind directly to host ports. |
| **Port Security** | **Port isolation**: Only NGINX exposes port 443 to the host. MariaDB (3306) and WordPress (9000) remain strictly private. | All container ports collide directly on the host machine. |
| **42 Compliance** | **Mandatory**. | **Strictly forbidden** (causes immediate failure). |

---

### 4. Docker Volumes vs. Bind Mounts

| Feature | Anonymous/Raw Bind Mounts | Docker Named Volumes with Bind Options |
| :--- | :--- | :--- |
| **Management** | Completely bypassed by Docker's volume subsystem. | Managed directly by Docker (`docker volume ls`, `docker volume inspect`). |
| **42 Requirement** | **Forbidden** when used as raw host paths in services. | **Required**: Declared under top-level `volumes:` in `docker-compose.yml`. |
| **Implementation** | Directly writing `/home/alnassar/data/wp:/var/www/html` under a service. | Configured with `driver: local` and `driver_opts: { type: bind, o: bind, device: /home/alnassar/data/... }`. |
| **Persistence** | Data stays on the host. | Combines Docker CLI management with full host persistence across reboots. |

---

## Process Lifecycle & PID 1 Policy

In Linux, **PID 1** is the first process launched. It has two essential responsibilities:
1. **Adopting orphan processes**: Reaps zombie child processes when their parent terminates.
2. **Signal handling**: Receives shutdown signals like `SIGTERM` and `SIGINT` from `docker stop`.

### Why `exec` is Mandatory:
In entrypoint shell scripts (`entrypoint.sh`, `setup.sh`), using `exec <command>` replaces the running shell process with the target executable. This guarantees that the actual daemon (`nginx`, `php-fpm83`, `mariadbd`) becomes **PID 1** and directly receives `SIGTERM` for a clean, non-corrupting shutdown.

### Prohibited Hacky Patches:
Commands like `tail -f /dev/null`, `sleep infinity`, or `while true; do sleep 1; done` are strictly forbidden. They trap PID 1 with a dummy command that ignores shutdown signals, causing data loss when stopping database containers.

---

## The Three Services Explained

### 1. NGINX (The Front Door)
- **Base Image**: `alpine:3.23`
- **Role**: Reverse proxy, TLS termination, and static file server.
- **Port**: Listens **only** on port `443` (HTTPS). Plain HTTP port `80` is closed.
- **Protocols**: Strictly `TLSv1.2` and `TLSv1.3`.
- **Static Assets**: Reads directly from `/var/www/html` mounted as **read-only (`:ro`)**.
- **Dynamic FastCGI**: Forwards `.php` requests to `wordpress:9000`.
- **PID 1**: `exec nginx -g "daemon off;"`

### 2. WordPress + PHP-FPM (The Engine)
- **Base Image**: `alpine:3.23` with PHP 8.3 (`php83-fpm`, `php83-mysqli`, `php83-curl`, etc.)
- **Role**: Executes PHP code and manages WordPress installation.
- **Port**: Listens on `0.0.0.0:9000` (FastCGI) inside the private bridge network.
- **Automation**: Uses **WP-CLI** to automatically download core files, generate `wp-config.php`, run installation, and create users.
- **Admin Username Rule**: Set to `alnassar_master` (complies with the 42 rule forbidding `admin` or `Admin`).
- **Second User**: Creates regular subscriber/author user `alnassar_user`.
- **PID 1**: `exec php-fpm83 -F`

### 3. MariaDB (The Database)
- **Base Image**: `alpine:3.23` with `mariadb`, `mariadb-client`
- **Role**: Relational database engine storing all WordPress tables.
- **Port**: Listens on `0.0.0.0:3306` inside the private bridge network.
- **User**: Runs strictly under the non-root system user `mysql`.
- **Initialization**: Automatically bootstraps the database, sets the `root` password, creates `wp_user`, and grants privileges using passwords from Docker secrets.
- **PID 1**: `exec mariadbd --user=mysql --datadir=/var/lib/mysql --console`

---

## Instructions & How to Run

### Prerequisites
1. Linux (Debian/Ubuntu, VM, or WSL2) with Docker Engine and Docker Compose (v2) installed.
2. Add the domain redirect to `/etc/hosts`:
   ```bash
   echo "127.0.0.1 alnassar.42.fr" | sudo tee -a /etc/hosts
   ```

### Makefile Targets
| Command | Action |
| :--- | :--- |
| `make` / `make up` | Create required host directories, verify secrets, build images, and launch all services in detached mode (`-d`). |
| `make down` | Stop and remove containers and internal networks (persistent data is preserved). |
| `make status` | Display status of running containers (`docker compose ps`). |
| `make logs` | Stream live logs from all running containers (`docker compose logs -f`). |
| `make restart` | Restart all services. |
| `make clean` | Stop containers and remove images and networks. |
| `make fclean` | Complete teardown: removes containers, networks, images, volumes, and deletes `/home/alnassar/data/*`. |
| `make re` | Full rebuild and restart from scratch (`fclean` + `up`). |

### Web Access
- **WordPress Website**: [https://alnassar.42.fr](https://alnassar.42.fr)
- **Admin Dashboard**: [https://alnassar.42.fr/wp-admin](https://alnassar.42.fr/wp-admin)
  - Admin User: `alnassar_master`
  - Admin Password: see `secrets/wp_admin_password.txt`

---

## Evaluation Day Playbook (Commands & Defense)

Follow these exact steps during your peer evaluation:

```bash
# 1. Clean build from scratch
make fclean
make up

# 2. Check running containers (Verify all show 'Up')
make status

# 3. Check port security (Only port 443 must be exposed to 0.0.0.0)
docker ps

# 4. Verify user-defined bridge network
docker network ls
docker network inspect inception_net

# 5. Verify named volumes and host storage paths (/home/alnassar/data/*)
docker volume ls
docker volume inspect db_data
docker volume inspect wp_data

# 6. Verify HTTP (port 80) fails
curl -I http://alnassar.42.fr

# 7. Verify TLS 1.2 and TLS 1.3 succeed
curl -kI --tlsv1.2 https://alnassar.42.fr
curl -kI --tlsv1.3 https://alnassar.42.fr

# 8. Verify outdated TLS versions (TLS 1.0 / 1.1) fail
curl -kI --tlsv1.1 https://alnassar.42.fr

# 9. Log into MariaDB and show tables
docker exec -it mariadb mariadb -u wp_user -p wordpress
# Enter password from secrets/db_password.txt
SHOW TABLES;
SELECT option_name, option_value FROM wp_options WHERE option_name = 'siteurl';
exit;

# 10. Verify PID 1 inside each container (No hacky patches!)
docker exec -it mariadb ps aux       # PID 1 is mariadbd
docker exec -it wordpress ps aux     # PID 1 is php-fpm83
docker exec -it nginx ps aux         # PID 1 is nginx
```

### Persistence Test:
1. Open `https://alnassar.42.fr/wp-admin`, log in, and write a new test post.
2. Stop the containers: `make down` (or reboot the VM).
3. Start the stack again: `make up`.
4. Refresh the page: the post remains intact because it was saved to `/home/alnassar/data/db`.

---

## Live Code Modification Guide (Changing a Port)

During defense, your evaluator is required to ask you to modify a service's configuration (usually changing a port) and verify that it still functions.

### Example: Change WordPress PHP-FPM Port from 9000 to 9001
Change the port number in these **4 files**:
1. `srcs/.env` $\rightarrow$ `PHP_FPM_PORT=9001`
2. `srcs/requirements/wordpress/conf/www.conf` $\rightarrow$ `listen = 0.0.0.0:9001`
3. `srcs/requirements/nginx/conf/nginx.conf` $\rightarrow$ `fastcgi_pass wordpress:9001;`
4. `srcs/requirements/wordpress/Dockerfile` $\rightarrow$ `EXPOSE 9001`

Apply the change:
```bash
make re
```
Open `https://alnassar.42.fr` $\rightarrow$ the site continues to load without errors.

---

## Automatic Fail Checklist (Instant 0 Traps)

Before submitting, ensure none of the following violations exist:
- [x] **No hardcoded passwords in Git**: No credentials committed outside of evaluation secret files.
- [x] **No prohibited Docker Compose directives**: No `network: host`, no `links:`, no `--link`.
- [x] **No infinite dummy loops**: No `tail -f`, no `sleep infinity`, no `while true` in entrypoints.
- [x] **No background process hacks**: No `nginx &` or `mariadb &` without `exec`.
- [x] **No pre-built images**: No `FROM wordpress`, `FROM nginx`, or `FROM mariadb` from DockerHub.
- [x] **Penultimate OS version**: Containers built strictly on Alpine 3.23 (or Debian penultimate).
- [x] **Correct Admin Username**: The administrator account does not contain `admin` or `Admin`.
- [x] **Port 80 is closed**: NGINX only responds on port 443 with TLS 1.2 or 1.3.
- [x] **Required Documentation**: `README.md`, `USER_DOC.md`, and `DEV_DOC.md` are present at the root.

---

## Resources & AI Usage Statement

### References:
- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose Specification](https://docs.docker.com/compose/compose-file/)
- [Alpine Linux Documentation](https://wiki.alpinelinux.org/)
- [NGINX Documentation & TLS Configuration](https://nginx.org/en/docs/)
- [PHP-FPM Configuration Guide](https://www.php.net/manual/en/install.fpm.configuration.php)
- [WP-CLI Command Handbook](https://make.wordpress.org/cli/handbook/)
- [MariaDB Knowledge Base](https://mariadb.com/kb/en/)

### Explanation of AI Usage:
In accordance with 42 guidelines (Chapter IV & Chapter VI):
- **Conceptual Clarification**: AI was utilized to draft study explanations and comparisons regarding Linux kernel mechanisms (Namespaces, Cgroups, and PID 1 signal propagation).
- **Configuration Review**: AI assisted in reviewing Dockerfiles and configuration files against 42 Inception subject requirements and security constraints.
- **Documentation Structuring**: AI helped structure and format clear, readable Markdown documentation (`README.md`, `USER_DOC.md`, and `DEV_DOC.md`).
- All code implementations, scripts, configurations, and architectural decisions were thoroughly understood, tested, and validated by the student.
