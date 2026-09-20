# Inception - User & Administrator Documentation (USER_DOC)

This guide provides basic operational instructions for an end user or system administrator managing the Inception web infrastructure.

---

## 1. Starting & Stopping the Infrastructure

All management operations are handled via the root `Makefile`:

- **Start the Stack**:
  ```bash
  make up
  ```
  *(This builds and runs all services in the background).*

- **Stop the Stack (Pause)**:
  ```bash
  make stop
  ```

- **Restart the Stack**:
  ```bash
  make restart
  ```

- **Teardown (Stop and remove containers/networks)**:
  ```bash
  make down
  ```

---

## 2. Accessing the Website & Administration Panel

### Domain Setup
Ensure the domain is mapped to `127.0.0.1` on the client/host machine (`/etc/hosts` on Linux/macOS or `C:\Windows\System32\drivers\etc\hosts` on Windows):
```text
127.0.0.1 alnassar.42.fr
```

### Web Access
- **Public Website**: Open [https://alnassar.42.fr](https://alnassar.42.fr) in your web browser.
  > **Note**: A self-signed certificate warning may appear. This is normal and expected because the certificate is generated locally for development. Accept the warning to proceed.
- **Administration Dashboard**: Open [https://alnassar.42.fr/wp-admin](https://alnassar.42.fr/wp-admin)

---

## 3. Managing Credentials & Accounts

### Pre-configured Accounts
- **WordPress Administrator**:
  - **Username**: `alnassar_master` *(Does NOT contain 'admin' or 'Admin' in compliance with 42 rules)*
  - **Password**: Stored in `secrets/wp_admin_password.txt`
  - **Email**: `alnassar_master@student.42.fr`
- **WordPress Regular User**:
  - **Username**: `alnassar_user`
  - **Password**: Stored in `secrets/wp_user_password.txt`
  - **Role**: `author`
- **MariaDB Database User**:
  - **Username**: `wp_user`
  - **Password**: Stored in `secrets/db_password.txt`
  - **Database**: `wordpress`
- **MariaDB Root User**:
  - **Username**: `root`
  - **Password**: Stored in `secrets/db_root_password.txt`

### Changing Passwords
To change passwords before initial deployment, edit the corresponding file in `secrets/`:
- `secrets/wp_admin_password.txt`
- `secrets/wp_user_password.txt`
- `secrets/db_password.txt`
- `secrets/db_root_password.txt`

> **Warning**: Modifying secret files after the initial deployment requires resetting the database or updating credentials inside the WordPress admin dashboard and database.

---

## 4. Basic System Checks

### Verify Container Status
Run:
```bash
make status
```
All three containers (`mariadb`, `wordpress`, `nginx`) should show `Up` status.

### Verify Port Exposure (Security Check)
Run:
```bash
docker ps
```
- **Port 443** must be the **only** port mapped to the host (`0.0.0.0:443->443/tcp`).
- Ports `3306` (MariaDB) and `9000` (WordPress) must **not** be mapped to the host.

### Test HTTPS & TLS Protocol
Verify that HTTP on port 80 fails and HTTPS on port 443 succeeds:
```bash
# HTTP must fail:
curl -I http://alnassar.42.fr

# HTTPS with TLS 1.2 must succeed:
curl -kI --tlsv1.2 https://alnassar.42.fr

# HTTPS with TLS 1.3 must succeed:
curl -kI --tlsv1.3 https://alnassar.42.fr
```
