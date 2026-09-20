#!/bin/bash
# ==============================================================================
# 42 Inception - Comprehensive Evaluation & Compliance Tester
# Based strictly on EVALUATION.md and en.subject.pdf (v5.3)
# ==============================================================================

set -uo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

pass() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "  [${GREEN}PASS${NC}] $1"
}

fail() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo -e "  [${RED}FAIL${NC}] $1"
    if [ -n "${2:-}" ]; then
        echo -e "         ${YELLOW}Reason: $2${NC}"
    fi
}

section() {
    echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}"
}

# Determine script root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BOLD}${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          42 INCEPTION EVALUATION AUTOMATED TESTER          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Read .env if available
DOMAIN_NAME="alnassar.42.fr"
WP_ADMIN_USER="alnassar_master"
if [ -f "srcs/.env" ]; then
    ENV_DOMAIN=$(grep -E '^DOMAIN_NAME=' srcs/.env | cut -d '=' -f2 | tr -d '\r"')
    [ -n "$ENV_DOMAIN" ] && DOMAIN_NAME="$ENV_DOMAIN"
    ENV_ADMIN=$(grep -E '^WP_ADMIN_USER=' srcs/.env | cut -d '=' -f2 | tr -d '\r"')
    [ -n "$ENV_ADMIN" ] && WP_ADMIN_USER="$ENV_ADMIN"
fi

# ==============================================================================
# SECTION 1: REPOSITORY & DIRECTORY STRUCTURE
# ==============================================================================
section "1. Repository & Directory Structure"

if [ -d "srcs" ]; then
    pass "Folder 'srcs' exists at root"
else
    fail "Folder 'srcs' missing at root"
fi

if [ -f "Makefile" ]; then
    pass "File 'Makefile' exists at root"
else
    fail "File 'Makefile' missing at root"
fi

if [ -f "srcs/docker-compose.yml" ]; then
    pass "File 'srcs/docker-compose.yml' exists"
else
    fail "File 'srcs/docker-compose.yml' missing"
fi

for svc in mariadb nginx wordpress; do
    if [ -d "srcs/requirements/$svc" ]; then
        pass "Folder 'srcs/requirements/$svc' exists"
    else
        fail "Folder 'srcs/requirements/$svc' missing"
    fi
    if [ -f "srcs/requirements/$svc/Dockerfile" ]; then
        pass "Dockerfile exists for '$svc'"
    else
        fail "Dockerfile missing for '$svc'"
    fi
done

# ==============================================================================
# SECTION 2: README & DOCUMENTATION REQUIREMENTS
# ==============================================================================
section "2. Documentation Checks (README, USER_DOC, DEV_DOC)"

if [ -f "README.md" ]; then
    FIRST_LINE=$(head -n 1 README.md)
    if echo "$FIRST_LINE" | grep -qE "^\*This project has been created as part of the 42 curriculum by .+\*"; then
        pass "README.md first line matches required italicized format"
    else
        fail "README.md first line format invalid" "Got: '$FIRST_LINE'"
    fi

    if grep -iq "## Description" README.md && grep -iq "## Instructions" README.md && grep -iq "## Resources" README.md; then
        pass "README.md contains Description, Instructions, and Resources sections"
    else
        fail "README.md missing one or more required sections"
    fi

    if grep -iq "AI" README.md; then
        pass "README.md contains AI usage explanation"
    else
        fail "README.md missing explanation of how AI was used"
    fi
else
    fail "README.md is missing at root"
fi

if [ -f "USER_DOC.md" ] && [ -s "USER_DOC.md" ]; then
    pass "USER_DOC.md exists and is not empty"
else
    fail "USER_DOC.md is missing or empty"
fi

if [ -f "DEV_DOC.md" ] && [ -s "DEV_DOC.md" ]; then
    pass "DEV_DOC.md exists and is not empty"
else
    fail "DEV_DOC.md is missing or empty"
fi

# ==============================================================================
# SECTION 3: FORBIDDEN SYNTAX & COMMAND CHECKS (Instant 0 Checks)
# ==============================================================================
section "3. Prohibited Syntax Checks (Subject Constraints)"

# docker-compose.yml checks
if [ -f "srcs/docker-compose.yml" ]; then
    if grep -qE "network:\s*host" srcs/docker-compose.yml; then
        fail "Found 'network: host' in srcs/docker-compose.yml (Forbidden!)"
    else
        pass "No 'network: host' in docker-compose.yml"
    fi

    if grep -qE "^\s*links:" srcs/docker-compose.yml; then
        fail "Found 'links:' in srcs/docker-compose.yml (Forbidden!)"
    else
        pass "No 'links:' in docker-compose.yml"
    fi

    if grep -qE "^\s*networks:" srcs/docker-compose.yml; then
        pass "'networks:' is declared in docker-compose.yml"
    else
        fail "Missing 'networks:' in docker-compose.yml"
    fi
fi

# Check for --link in all files
LINK_MATCHES=$(grep -rn --exclude-dir=".git" --exclude="*.md" --exclude="*.pdf" --exclude="test_eval.sh" "\--link" . 2>/dev/null || true)
if [ -n "$LINK_MATCHES" ]; then
    fail "Found '--link' in project files" "$LINK_MATCHES"
else
    pass "No '--link' used anywhere in scripts/Makefiles"
fi

# Check for tail -f, sleep infinity, while true in scripts/Dockerfiles
BAD_LOOPS=$(grep -rnE --exclude-dir=".git" --exclude="*.md" --exclude="*.pdf" --exclude="test_eval.sh" "(tail\s+-f|sleep\s+infinity|while\s+true)" . 2>/dev/null || true)
if [ -n "$BAD_LOOPS" ]; then
    fail "Found prohibited infinite loops / hacky patches" "$BAD_LOOPS"
else
    pass "No 'tail -f', 'sleep infinity', or infinite loops in code"
fi

# Check Dockerfiles for penultimate OS (Alpine 3.23 or Debian)
for svc in mariadb nginx wordpress; do
    DF="srcs/requirements/$svc/Dockerfile"
    if [ -f "$DF" ]; then
        FROM_LINE=$(grep -E "^\s*FROM" "$DF" | head -n 1)
        if echo "$FROM_LINE" | grep -qE "alpine:(3\.23)"; then
            pass "Service '$svc' uses Alpine 3.23 ($FROM_LINE)"
        elif echo "$FROM_LINE" | grep -qiE "debian"; then
            pass "Service '$svc' uses Debian ($FROM_LINE)"
        else
            fail "Service '$svc' Dockerfile does not use Alpine 3.23 or Debian" "Got: $FROM_LINE"
        fi

        # Check for ready-made images
        if echo "$FROM_LINE" | grep -qiE "(wordpress|mariadb|mysql|nginx):"; then
            fail "Service '$svc' uses forbidden ready-made image!" "Got: $FROM_LINE"
        else
            pass "Service '$svc' does not use pre-made images"
        fi

        # Check that wordpress/mariadb don't install/contain nginx
        if [ "$svc" != "nginx" ]; then
            if grep -qiE "apk add.*nginx" "$DF"; then
                fail "Service '$svc' installs nginx in Dockerfile (Forbidden!)"
            else
                pass "Service '$svc' does not install nginx"
            fi
        fi
    fi
done

# Check admin username rule
if echo "$WP_ADMIN_USER" | grep -qi "admin"; then
    fail "Admin username '$WP_ADMIN_USER' contains 'admin' or 'Admin' (Forbidden!)"
else
    pass "Admin username '$WP_ADMIN_USER' does NOT contain 'admin' or 'Admin'"
fi

# ==============================================================================
# SECTION 4: RUNNING CONTAINERS & DOCKER ENGINE STATUS
# ==============================================================================
section "4. Live Docker Container & Service Status"

# Check if containers are running
for svc in nginx wordpress mariadb; do
    if docker ps --format '{{.Names}}' | grep -q "^${svc}$"; then
        pass "Container '${svc}' is running"
    else
        fail "Container '${svc}' is NOT running" "Run 'make up' to start the stack"
    fi
done

# ==============================================================================
# SECTION 5: PORT EXPOSURE & SECURITY
# ==============================================================================
section "5. Port Security & Network Isolation"

# Port 443 must be exposed to host
NGINX_PORTS=$(docker port nginx 2>/dev/null || true)
if echo "$NGINX_PORTS" | grep -q "443/tcp"; then
    pass "NGINX exposes port 443 to host ($NGINX_PORTS)"
else
    fail "NGINX does NOT expose port 443 to host"
fi

# Port 80 must NOT be exposed
if echo "$NGINX_PORTS" | grep -q "80/tcp"; then
    fail "NGINX exposes port 80 (Forbidden: only port 443 is allowed!)"
else
    pass "Port 80 is NOT exposed on NGINX"
fi

# MariaDB (3306) and WordPress (9000) must NOT be exposed to host
WP_PORTS=$(docker port wordpress 2>/dev/null || true)
if [ -n "$WP_PORTS" ]; then
    fail "WordPress exposes ports to host! ($WP_PORTS)"
else
    pass "WordPress port 9000 is private (NOT exposed to host)"
fi

DB_PORTS=$(docker port mariadb 2>/dev/null || true)
if [ -n "$DB_PORTS" ]; then
    fail "MariaDB exposes ports to host! ($DB_PORTS)"
else
    pass "MariaDB port 3306 is private (NOT exposed to host)"
fi

# Check user-defined bridge network
NETWORKS=$(docker network ls --format '{{.Name}}')
if echo "$NETWORKS" | grep -qE "(inception|inception_net)"; then
    pass "User-defined network exists in Docker"
else
    fail "No user-defined inception network found"
fi

# ==============================================================================
# SECTION 6: VOLUMES & PERSISTENCE
# ==============================================================================
section "6. Volume Configuration & Persistence"

VOLUMES=$(docker volume ls --format '{{.Name}}')
if echo "$VOLUMES" | grep -q "db_data"; then
    pass "Named volume 'db_data' exists"
    DB_MOUNT=$(docker volume inspect db_data --format '{{.Options.device}}' 2>/dev/null || echo "")
    if echo "$DB_MOUNT" | grep -q "/home/"; then
        pass "Volume 'db_data' points to host /home/... path ($DB_MOUNT)"
    else
        fail "Volume 'db_data' device option not pointing to /home/..." "Got: $DB_MOUNT"
    fi
else
    fail "Named volume 'db_data' not found"
fi

if echo "$VOLUMES" | grep -q "wp_data"; then
    pass "Named volume 'wp_data' exists"
    WP_MOUNT=$(docker volume inspect wp_data --format '{{.Options.device}}' 2>/dev/null || echo "")
    if echo "$WP_MOUNT" | grep -q "/home/"; then
        pass "Volume 'wp_data' points to host /home/... path ($WP_MOUNT)"
    else
        fail "Volume 'wp_data' device option not pointing to /home/..." "Got: $WP_MOUNT"
    fi
else
    fail "Named volume 'wp_data' not found"
fi

# ==============================================================================
# SECTION 7: SSL / TLS PROTOCOL TESTING
# ==============================================================================
section "7. SSL/TLS Verification (Port 443, TLS 1.2 & 1.3)"

# Check HTTP fails
if curl -s --connect-timeout 3 "http://127.0.0.1:80" >/dev/null 2>&1; then
    fail "HTTP on port 80 is responding! (Port 80 should be closed/refused)"
else
    pass "HTTP on port 80 fails as expected (Connection refused/closed)"
fi

# Check HTTPS TLS 1.2
TLS12_RES=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --tlsv1.2 --tls-max 1.2 --resolve "${DOMAIN_NAME}:443:127.0.0.1" "https://${DOMAIN_NAME}" 2>/dev/null || echo "FAIL")
if [ "$TLS12_RES" != "FAIL" ] && [ "$TLS12_RES" != "000" ]; then
    pass "HTTPS with TLSv1.2 succeeds (HTTP code: $TLS12_RES)"
else
    fail "HTTPS with TLSv1.2 failed to connect"
fi

# Check HTTPS TLS 1.3
TLS13_RES=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --tlsv1.3 --tls-max 1.3 --resolve "${DOMAIN_NAME}:443:127.0.0.1" "https://${DOMAIN_NAME}" 2>/dev/null || echo "FAIL")
if [ "$TLS13_RES" != "FAIL" ] && [ "$TLS13_RES" != "000" ]; then
    pass "HTTPS with TLSv1.3 succeeds (HTTP code: $TLS13_RES)"
else
    fail "HTTPS with TLSv1.3 failed to connect"
fi

# Check old TLS 1.1 fails
if curl -k -s --connect-timeout 5 --tlsv1.1 --tls-max 1.1 --resolve "${DOMAIN_NAME}:443:127.0.0.1" "https://${DOMAIN_NAME}" >/dev/null 2>&1; then
    fail "Outdated TLSv1.1 was accepted (Security risk!)"
else
    pass "Outdated TLSv1.1 is correctly rejected"
fi

# ==============================================================================
# SECTION 8: PROCESS MANAGEMENT & PID 1 VERIFICATION
# ==============================================================================
section "8. Process Management & PID 1 Policy"

# Check MariaDB PID 1
DB_PID1=$(docker exec mariadb ps -o pid,comm 2>/dev/null | awk '$1 == 1 {print $2}' || true)
if echo "$DB_PID1" | grep -qiE "(mariadbd|mysqld)"; then
    pass "MariaDB PID 1 is the database daemon ($DB_PID1)"
else
    fail "MariaDB PID 1 is NOT mariadbd" "Got: '$DB_PID1'"
fi

# Check WordPress PID 1
WP_PID1=$(docker exec wordpress ps -o pid,comm 2>/dev/null | awk '$1 == 1 {print $2}' || true)
if echo "$WP_PID1" | grep -qiE "php-fpm"; then
    pass "WordPress PID 1 is php-fpm ($WP_PID1)"
else
    fail "WordPress PID 1 is NOT php-fpm" "Got: '$WP_PID1'"
fi

# Check NGINX PID 1
NGINX_PID1=$(docker exec nginx ps -o pid,comm 2>/dev/null | awk '$1 == 1 {print $2}' || true)
if echo "$NGINX_PID1" | grep -qiE "nginx"; then
    pass "NGINX PID 1 is nginx ($NGINX_PID1)"
else
    fail "NGINX PID 1 is NOT nginx" "Got: '$NGINX_PID1'"
fi

# ==============================================================================
# SECTION 9: WORDPRESS & MARIADB APPLICATION DATA
# ==============================================================================
section "9. WordPress & MariaDB Application Data"

# Check if database is populated via wp_user connecting through 127.0.0.1
DB_PASS="$(tr -d '\r\n' < secrets/db_password.txt 2>/dev/null || echo '')"
DB_TABLE_COUNT=$(docker exec mariadb mariadb -h 127.0.0.1 -u wp_user -p"${DB_PASS}" wordpress -e "SHOW TABLES;" 2>/dev/null | grep -c "wp_" || echo "0")
if [ "$DB_TABLE_COUNT" -gt 0 ]; then
    pass "MariaDB database 'wordpress' is populated ($DB_TABLE_COUNT WordPress tables found)"
else
    fail "MariaDB database 'wordpress' appears empty or cannot connect"
fi

# Check WordPress site URL configuration
WP_SITEURL=$(docker exec wordpress wp option get siteurl --allow-root --path=/var/www/html 2>/dev/null || echo "")
if [ -n "$WP_SITEURL" ]; then
    pass "WordPress is properly installed (siteurl: $WP_SITEURL)"
else
    fail "WordPress is not fully installed or wp-cli cannot read siteurl"
fi

# Check WordPress users
WP_USER_COUNT=$(docker exec wordpress wp user list --format=count --allow-root --path=/var/www/html 2>/dev/null || echo "0")
if [ "$WP_USER_COUNT" -ge 2 ]; then
    pass "WordPress has at least 2 users configured ($WP_USER_COUNT users found)"
else
    fail "WordPress should have at least 2 users (found: $WP_USER_COUNT)"
fi

# ==============================================================================
# SUMMARY REPORT
# ==============================================================================
echo ""
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}                     TEST SUMMARY REPORT                    ${NC}"
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "Total Checks Executed : ${BOLD}$TOTAL_TESTS${NC}"
echo -e "Passed Checks         : ${GREEN}${BOLD}$PASSED_TESTS${NC}"
echo -e "Failed Checks         : ${RED}${BOLD}$FAILED_TESTS${NC}"

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo ""
    echo -e "${GREEN}${BOLD}🎉 ALL CHECKS PASSED! Your project 100% conforms to the 42 evaluation sheet.${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}${BOLD}⚠️  SOME CHECKS FAILED! Review the items marked [FAIL] above before evaluation.${NC}"
    exit 1
fi
