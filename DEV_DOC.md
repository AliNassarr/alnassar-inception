# Inception - Developer & Maintainer Documentation (DEV_DOC)

This guide provides technical specifications, development guidelines, and architecture details for developers working on the Inception infrastructure.

---

## 1. Prerequisites & Environment Setup

### Required Tools
- **Linux Distribution**: Debian 12 / Ubuntu 22.04+ (or WSL2 / macOS).
- **Docker Engine**: Version 24.0+
- **Docker Compose**: Version 2.20+ (`docker compose`)
- **Make**: GNU Make 4.3+
- **OpenSSL**: Version 1.1.1 or 3.0+

### System Hosts Configuration
Map the project domain to localhost:
```bash
echo "127.0.0.1 alnassar.42.fr" | sudo tee -a /etc/hosts
```

---

## 2. Project Architecture & Components

```
Host (alnassar.42.fr:443)
       │
       ▼ (TLSv1.2 / TLSv1.3)
┌──────────────┐
│    NGINX     │ (Port 443 exposed)
└──────┬───────┘
       │ FastCGI (port 9000 - private bridge network)
       ▼
┌──────────────┐
│  WordPress   │ (PHP-FPM 8.3)
└──────┬───────┘
       │ TCP (port 3306 - private bridge network)
       ▼
┌──────────────┐
│   MariaDB    │ (Database engine)
└──────────────┘
```

### Docker Network
All containers communicate through the user-defined bridge network `inception_net`. Docker provides internal DNS resolution at `127.0.0.11`, enabling services to resolve each other by container name (`mariadb`, `wordpress`, `nginx`).

---

## 3. Makefile Usage & Development Targets

The root `Makefile` orchestrates all lifecycle commands:

| Command | Description |
|---|---|
| `make` / `make all` | Default target; checks prerequisites and runs `make up`. |
| `make up` | Builds images and starts containers in detached mode (`-d`). |
| `make down` | Stops and removes containers and the `inception_net` network. |
| `make start` | Starts existing stopped containers. |
| `make stop` | Pauses running containers without removing them. |
| `make restart` | Restarts all containers. |
| `make status` | Displays container statuses (`docker compose ps`). |
| `make logs` | Streams live logs from all services (`docker compose logs -f`). |
| `make clean` | Stops and removes containers and networks. |
| `make fclean` | Complete purge: removes containers, networks, images, volumes, and `/home/alnassar/data/*`. |
| `make re` | Rebuilds and launches the entire stack from scratch (`fclean` + `all`). |

---

## 4. Docker Compose Commands Reference

Developers can also run direct `docker compose` commands from within the `srcs/` directory or with `-f srcs/docker-compose.yml`:

```bash
# Build images explicitly
docker compose -f srcs/docker-compose.yml build

# Check service configuration and variables
docker compose -f srcs/docker-compose.yml config

# Inspect running processes
docker compose -f srcs/docker-compose.yml top

# Execute an interactive shell inside a service
docker compose -f srcs/docker-compose.yml exec wordpress sh
docker compose -f srcs/docker-compose.yml exec mariadb sh
docker compose -f srcs/docker-compose.yml exec nginx sh
```

---

## 5. Data Persistence & Volume Management

### Named Volumes
The subject mandates using **Docker named volumes** backed by `/home/login/data`. In `srcs/docker-compose.yml`:
```yaml
volumes:
  db_data:
    name: db_data
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${HOST_DB_PATH}
  wp_data:
    name: wp_data
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${HOST_WP_PATH}
```

### Host Directories
- **WordPress Data**: `/home/alnassar/data/wp` $\rightarrow$ Mounted to `/var/www/html` in `wordpress` and `/var/www/html:ro` in `nginx`.
- **Database Data**: `/home/alnassar/data/db` $\rightarrow$ Mounted to `/var/lib/mysql` in `mariadb`.

### Verifying Data Persistence
1. Start the stack: `make up`
2. Create a test post in WordPress at [https://alnassar.42.fr/wp-admin](https://alnassar.42.fr/wp-admin).
3. Tear down the containers: `make down`
4. Inspect the host directories to verify the physical files remain:
   ```bash
   ls -la /home/alnassar/data/wp
   ls -la /home/alnassar/data/db
   ```
5. Re-launch the containers: `make up`
6. Refresh the browser; the post and configuration remain intact.

---

## 6. Process Lifecycle & PID 1 Policy

In accordance with 42 guidelines:
- **No Background Processes**: All services must run as PID 1 in the foreground:
  - MariaDB: `exec mariadbd --user=mysql --datadir=/var/lib/mysql --console`
  - WordPress (PHP-FPM): `exec php-fpm83 -F`
  - NGINX: `exec nginx -g "daemon off;"`
- **No Prohibited Commands**: Scripts must not contain `tail -f`, `sleep infinity`, or infinite `while` loops.
