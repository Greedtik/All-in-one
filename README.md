# Enterprise Master Operations Tool v4.0

A centralized, all-in-one bash automation script designed for Linux system administration. This tool streamlines the process of virtual machine provisioning, monitoring setup, security scanning, and post-migration auditing into a single interactive menu.

## 🚀 Features

This script consolidates four major operational tasks into an easy-to-use interactive menu:

1. **First setup-vm (VM Provisioning)**
   - Automatically detects OS (Debian/Ubuntu/CentOS/RHEL).
   - Updates system packages and cleans up old dependencies.
   - Installs essential system tools (htop, vim, curl, jq, net-tools, etc.).
   - Installs and enables `qemu-guest-agent`.
   - Configures timezone to `Asia/Bangkok` and enables time synchronization.
   - Applies basic SSH hardening (disables/enables password auth based on user input).

2. **SNMP Install**
   - Automatically installs `snmpd` and `snmp` packages.
   - Prompts for a custom SNMP Community String (defaults to `public`).
   - Hardens SNMP configuration with View-Based Access Control (VACM), restricting access to `systemonly` (.1).
   - Runs a self-test (`snmpwalk`) locally to verify installation.

3. **Soc Scanner (Incident Response Tool)**
   - **Malware & Miner Scan:** Checks for known crypto-miners (xmrig, kinsing) and hidden executables in `/tmp`.
   - **Reverse Shell Scan:** Detects active suspicious shell connections (bash, sh, zsh).
   - **Port Scan:** Audits listening ports against a list of commonly abused ports (4444, 31337, etc.).
   - **User Audit:** Checks for rogue `UID 0` accounts and accounts with empty passwords.
   - **Persistence Scan:** Audits `cron` jobs for suspicious payloads (curl, wget, base64).
   - **Docker Scan:** Identifies privileged Docker containers.
   - **CVE Vulnerability Scan:** Queries the OSV API to check for vulnerabilities in critical packages (e.g., `sudo`).

4. **Migration Health Check**
   - Performs a comprehensive post-migration system audit.
   - Checks System Load, Uptime, Kernel, and Storage/Inode usage.
   - Verifies all `/etc/fstab` mount points.
   - Tests Network Connectivity (Gateway, Internet, DNS).
   - Checks core services status (sshd, nginx, apache2, mysql, etc.).
   - Scans for Enterprise Suites (Zimbra, cPanel) and custom applications in `/opt`.
   - Generates a detailed Executive Summary report saved to `/var/log/migration_audit_<date>.log`.

## ⚙️ Requirements

- **OS:** Debian, Ubuntu, CentOS, RHEL, Rocky Linux, or AlmaLinux.
- **Privileges:** Must be executed as `root` (or via `sudo`).

## 🛠️ Usage

You can run this master script directly from the Git repository without needing to clone it locally.

**Method 1: Run via bash Process Substitution (Recommended for Interactive Menus)**
Ensure you are logged in as `root` or use `sudo` before executing:

```bash
bash <(curl -sL https://raw.githubusercontent.com/Greedtik/All-in-one/refs/heads/main/all-in-one.sh)
