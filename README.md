*This project has been created as part of the 42 curriculum by alnassar.*

# Inception

## Description
**Inception** is a system administration and DevOps project in the 42 curriculum. The objective is to design, configure, and deploy a secure, multi-container microservice web infrastructure using **Docker** and **Docker Compose**.

All services run inside isolated Docker containers built from custom `Dockerfile`s based on the penultimate stable version of **Alpine Linux (v3.23)**. The infrastructure strictly forbids pre-built images from DockerHub and consists of:
- **NGINX**: Acts as the sole entrypoint to the infrastructure, strictly accepting connections over **port 443** using **TLSv1.2 or TLSv1.3**.
- **WordPress + PHP-FPM**: Serves the dynamic WordPress application. Communicates privately with NGINX via **FastCGI on port 9000** inside the private bridge network.
- **MariaDB**: Relational database engine storing all WordPress data. Accessible privately at **port 3306** within the internal network.
- **Docker Volumes**: Dedicated named volumes mapped to `/home/alnassar/data/wp` and `/home/alnassar/data/db` to ensure persistent storage across restarts and reboot cycles.
- **Docker Secrets**: In-memory encrypted secrets mounted at `/run/secrets/` to prevent sensitive credentials and passwords from being exposed in environment variables or Git repositories.

---

## Instructions

### Prerequisites
- Operating System: Linux (Debian/Ubuntu recommended) or macOS / WSL2.
- Docker Engine & Docker Compose (v2 recommended).
- `make` utility.
- Add domain mapping to `/etc/hosts`:
  ```bash
  echo "127.0.0.1 alnassar.42.fr" | sudo tee -a /etc/hosts
  ```

### Running the Stack
1. Clone the repository and navigate into it:
   ```bash
   git clone <repository_url> Inception && cd Inception
   ```
2. Build and launch all services:
   ```bash
   make
   ```
3. Open your browser and navigate to:
   - **WordPress Site**: [https://alnassar.42.fr](https://alnassar.42.fr)
   - **Admin Dashboard**: [https://alnassar.42.fr/wp-admin](https://alnassar.42.fr/wp-admin)
     - Username: `alnassar_master`
     - Password: see `secrets/wp_admin_password.txt`

### Common Commands
- `make up` - Build and start all containers in the background.
- `make down` - Stop and remove containers and networks.
- `make status` - View the running status of containers.
- `make logs` - Stream logs from all services.
- `make restart` - Restart all running services.
- `make clean` - Stop and remove containers.
- `make fclean` - Full cleanup: remove containers, networks, images, volumes, and host data directories.
- `make re` - Rebuild and restart the entire stack from scratch.

---

## Core Concepts & Defense Q&A

### 1. Docker Image vs. Docker Container
* **Docker Image**:
  - A read-only template/blueprint containing the application code, libraries, and runtime environment.
  - Stored on disk; immutable once built.
* **Docker Container**:
  - A running, active instance created from an image.
  - An isolated process running on the host kernel with its own virtualized filesystem, network, and process space.

### 2. Virtual Machine (VM) vs. Docker Container
* **Virtual Machine**:
  - Uses a **Hypervisor** (e.g., VirtualBox, KVM) to emulate virtual hardware (vCPU, RAM, NIC).
  - Runs a complete, independent **Guest Operating System** with its own kernel.
  - Higher resource overhead (gigabytes of RAM) and slower startup (30–60 seconds).
* **Docker Container**:
  - Has **no guest OS** and no hypervisor.
  - Runs as native processes directly on the **shared Host Linux Kernel**.
  - Uses Linux kernel **Namespaces** (for visibility isolation) and **Cgroups** (for resource quotas).
  - Near-instant startup (milliseconds) with minimal overhead.

### 3. Plain Docker vs. Docker Compose
* **Plain Docker (`docker run`)**:
  - Manages individual containers via standalone CLI commands.
  - Manual network linking and volume management.
* **Docker Compose (`docker-compose.yml`)**:
  - Declarative orchestration tool for multi-container applications.
  - Manages services, networks, volumes, and secrets together as a unified stack with a single command (`docker compose up`).
  - Automatically provisions an isolated internal bridge network with built-in DNS resolution.

### 4. Process Management & PID 1 Policy
* **Why PID 1 Matters**:
  - A container's lifecycle is tied directly to its **PID 1** process. If PID 1 terminates, the container stops.
  - PID 1 receives Unix signals (such as `SIGTERM` when running `docker stop`). A proper daemon handles `SIGTERM` to perform a graceful shutdown without corrupting database files.
* **Why `exec` is Used**:
  - In entrypoint scripts, `exec <daemon>` replaces the temporary shell process with the target executable, preserving **PID 1** for the daemon.
* **Prohibited Hacky Patches**:
  - Commands like `tail -f /dev/null`, `sleep infinity`, or `while true` are strictly forbidden because they turn a dummy process into PID 1, preventing clean signal handling and risking data loss.

### 5. Docker Networking: Bridge vs. Host
* **User-Defined Bridge Network (`inception_net`)**:
  - Private, isolated virtual network switch created inside the Linux kernel.
  - Containers discover each other via Docker's embedded DNS server (`127.0.0.11`) using service names (`mariadb:3306`, `wordpress:9000`).
  - **Port Isolation**: Only NGINX publishes port `443` to the host. MariaDB and WordPress communicate strictly within the internal bridge network.
* **Host Network (`network: host`)**:
  - Removes all network isolation, attaching containers directly to host interfaces. Strictly forbidden by 42 rules.

### 6. Storage: Named Volumes vs. Bind Mounts
* **The 42 Requirement**:
  - Persistent data must be stored in `/home/alnassar/data/db` and `/home/alnassar/data/wp` using **Docker named volumes**.
  - Raw anonymous host bind mounts are prohibited because they bypass Docker's volume lifecycle management (`docker volume ls`, `docker volume inspect`).
* **Implementation**:
  - We configure named volumes using Docker's `local` driver with `driver_opts: { type: none, o: bind, device: ... }`, combining Docker's volume API with host persistence.

### 7. Security: Docker Secrets vs. Environment Variables
* **Environment Variables (`.env`)**:
  - Stored in the container's process descriptor; visible in `docker inspect` and `/proc/<pid>/environ`. Suitable only for non-sensitive settings (`DOMAIN_NAME`, `MYSQL_USER`).
* **Docker Secrets**:
  - Passwords and keys stored in outside files and mounted in-memory on a `tmpfs` temporary RAM filesystem (`/run/secrets/`). Never written to container disk or exposed in inspection commands.

---

## Resources

### Documentation & References
- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose File Reference](https://docs.docker.com/compose/compose-file/)
- [Alpine Linux Package Management](https://wiki.alpinelinux.org/wiki/Alpine_Package_Keeper)
- [NGINX Documentation & SSL Configuration](https://nginx.org/en/docs/)
- [PHP-FPM Configuration Guide](https://www.php.net/manual/en/install.fpm.configuration.php)
- [WP-CLI Official Handbook](https://make.wordpress.org/cli/handbook/)
- [MariaDB Server Knowledge Base](https://mariadb.com/kb/en/)

### Explanation of AI Usage
In accordance with 42 guidelines, AI tools were utilized during this project for:
- Formulating educational explanations and study flashcards on Linux kernel primitives (Namespaces, Cgroups, and PID 1 signal handling).
- Reviewing Docker configuration files and scripts against 42 Inception evaluation criteria.
- Assisting in structuring clear user and developer documentation (`USER_DOC.md`, `DEV_DOC.md`).
All architectural decisions, code implementations, Dockerfiles, and automation scripts were thoroughly understood, tested, and validated by the student.
