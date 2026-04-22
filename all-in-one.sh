#!/bin/bash

# ==============================================================================
# Enterprise Master Operations Tool (All-in-One based on Custom Scripts)
# ==============================================================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ตรวจสอบสิทธิ์ Root สำหรับ Master Script
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Error: Please run this script as root (e.g., using sudo).${NC}"
  exit 1
fi

trap 'echo -e "\n${RED}[!] Operation cancelled by user. Exiting...${NC}"; exit 1' SIGINT

# ==============================================================================
# 1. VM Provisioning (setup-vm.sh)
# ==============================================================================
func_setup_vm() {
    (
        LOG_FILE="/var/log/vm-provisioning.log"
        > "$LOG_FILE" # เคลียร์ไฟล์เก่า

        echo "Starting Provisioning Script... Log will be saved to $LOG_FILE"
        # ส่งเฉพาะ Output ของ UI ไปที่หน้าจอและ Log
        exec > >(tee -a "$LOG_FILE") 2>&1

        echo "=========================================="
        echo "    Universal VM Provisioning Script      "
        echo "=========================================="

        # 1. Interactive Input
        read -p "[?] Allow SSH Password Authentication? (y/n): " ssh_pass_choice < /dev/tty

        # ==========================================
        # Functions for Progress & Logging
        # ==========================================
        TOTAL_STEPS=7
        CURRENT_STEP=0

        show_progress() {
            CURRENT_STEP=$((CURRENT_STEP + 1))
            echo -e "\n=========================================="
            echo -e "Step ${CURRENT_STEP}/${TOTAL_STEPS}: $1"
            echo -e "=========================================="
        }

        print_sub() {
            local pct=$1
            local msg=$2
            printf "\r    -> [%3d%%] %-45s\e[K" "$pct" "$msg"
        }

        print_success() {
            local msg=$1
            printf "\r    [+] %-50s\e[K\n" "$msg"
        }

        print_error() {
            local msg=$1
            printf "\r    [!] %-50s\e[K\n" "$msg"
        }

        log_separator() {
            # ขึ้นบรรทัดใหม่ก่อนเขียนลง Log เพื่อแก้ปัญหาข้อความซ้อนทับจาก \r
            echo -e "\n\n[LOG] === $1 ===" >> "$LOG_FILE"
        }

        # ==========================================
        # Step 1: ตรวจสอบ OS และเตรียมตัวแปร
        # ==========================================
        show_progress "Detecting OS and Setting up Variables"
        log_separator "Starting OS Detection"

        print_sub 33 "Reading /etc/os-release..."
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS=$ID
            OS_FAMILY=$ID_LIKE
            print_success "Identified OS: $PRETTY_NAME"
        else
            echo -e "\nError: Cannot identify OS"
            exit 1
        fi

        print_sub 66 "Setting up package manager variables..."
        if [[ "$OS" == "ubuntu" || "$OS" == "debian" || "$OS_FAMILY" == *"debian"* ]]; then
            # แก้บั๊ก: ประกาศตัวแปรแบบ Global สำหรับ OS ตระกูล Debian
            export DEBIAN_FRONTEND=noninteractive
            PKG_UPDATE="apt-get update"
            PKG_UPGRADE="apt-get upgrade -y"
            PKG_CLEAN="apt-get autoremove -y"
            PKG_INSTALL="apt-get install -y"
            TOOLS=(psmisc htop vim curl wget jq net-tools tar unzip qemu-guest-agent systemd-timesyncd)
            FW_STOP="systemctl stop ufw"
            FW_DISABLE="systemctl disable ufw"
            TIME_SVC="systemd-timesyncd"
        elif [[ "$OS" == "centos" || "$OS" == "rocky" || "$OS" == "almalinux" || "$OS" == "rhel" || "$OS_FAMILY" == *"rhel"* ]]; then
            PKG_UPDATE="dnf makecache"
            PKG_UPGRADE="dnf upgrade -y"
            PKG_CLEAN="dnf autoremove -y"
            PKG_INSTALL="dnf install -y"
            TOOLS=(epel-release htop vim curl wget jq net-tools tar unzip qemu-guest-agent chrony)
            FW_STOP="systemctl stop firewalld"
            FW_DISABLE="systemctl disable firewalld"
            TIME_SVC="chronyd"
        fi
        print_success "Package manager configured"

        print_sub 100 "Detecting SSH service name..."
        if systemctl list-unit-files | grep -q "^sshd.service"; then
            SSH_SVC="sshd"
        else
            SSH_SVC="ssh"
        fi
        print_success "SSH service identified as '$SSH_SVC'"

        # ==========================================
        # Step 2: อัปเดตระบบ
        # ==========================================
        show_progress "Updating System Packages"
        log_separator "System Update Process"

        if [[ "$OS_FAMILY" == *"debian"* ]]; then
            print_sub 10 "Waiting for other package managers to finish..."
            if command -v fuser >/dev/null 2>&1; then
                while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
                    sleep 5
                done
            fi
            print_success "System ready for package management"
        fi

        print_sub 33 "Updating repository lists..."
        eval "$PKG_UPDATE" >> "$LOG_FILE" 2>&1
        print_success "Repository lists updated"

        print_sub 66 "Upgrading installed packages..."
        eval "$PKG_UPGRADE" >> "$LOG_FILE" 2>&1
        print_success "System packages upgraded"

        print_sub 100 "Cleaning up unnecessary files..."
        eval "$PKG_CLEAN" >> "$LOG_FILE" 2>&1
        print_success "Cleanup completed"

        # ==========================================
        # Step 3: ติดตั้ง Tools และ QEMU Agent
        # ==========================================
        show_progress "Installing Essential Tools and QEMU Agent"
        log_separator "Tools Installation Process"

        TOTAL_TOOLS=${#TOOLS[@]}
        CURRENT_TOOL=0

        for tool in "${TOOLS[@]}"; do
            CURRENT_TOOL=$((CURRENT_TOOL + 1))
            TOOL_PCT=$((CURRENT_TOOL * 100 / TOTAL_TOOLS))
            
            print_sub "$TOOL_PCT" "Installing $tool..."
            
            echo -e "\n[LOG] Installing: $tool" >> "$LOG_FILE"
            $PKG_INSTALL "$tool" >> "$LOG_FILE" 2>&1
            
            if [ $? -eq 0 ]; then
                print_success "Installed package: $tool"
            else
                print_error "FAILED to install package: $tool"
            fi
        done

        print_sub 100 "Enabling QEMU Guest Agent..."
        systemctl enable --now qemu-guest-agent >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            print_success "QEMU Guest Agent configuration applied"
        else
            print_error "FAILED to enable QEMU Guest Agent"
        fi

        # ==========================================
        # Step 4: ปิด Firewall
        # ==========================================
        show_progress "Disabling Firewall"
        log_separator "Firewall Configuration"

        print_sub 50 "Stopping firewall service..."
        eval "$FW_STOP" >> "$LOG_FILE" 2>&1 || true
        print_success "Firewall service stopped"

        print_sub 100 "Disabling firewall on boot..."
        eval "$FW_DISABLE" >> "$LOG_FILE" 2>&1 || true
        print_success "Firewall disabled from boot"

        # ==========================================
        # Step 5: ตั้งค่า Timezone และ Time Sync
        # ==========================================
        show_progress "Configuring Timezone and Time Sync"
        log_separator "Timezone and Sync Process"

        print_sub 33 "Setting timezone to Asia/Bangkok..."
        timedatectl set-timezone Asia/Bangkok >> "$LOG_FILE" 2>&1
        print_success "Timezone set to Asia/Bangkok"

        print_sub 66 "Enabling time sync service ($TIME_SVC)..."
        systemctl enable "$TIME_SVC" >> "$LOG_FILE" 2>&1
        print_success "Time sync service enabled"

        print_sub 100 "Starting time sync service..."
        systemctl restart "$TIME_SVC" >> "$LOG_FILE" 2>&1
        print_success "Time synchronization is now active"

        # ==========================================
        # Step 6: ตั้งค่า SSH
        # ==========================================
        show_progress "Configuring SSH Access"
        log_separator "SSH Configuration"

        SSH_CONF="/etc/ssh/sshd_config"
        print_sub 33 "Backing up sshd_config..."
        cp $SSH_CONF "${SSH_CONF}.bak"
        print_success "Backup created at ${SSH_CONF}.bak"

        print_sub 66 "Applying PasswordAuthentication rule..."
        if [[ "$ssh_pass_choice" == "n" || "$ssh_pass_choice" == "N" ]]; then
            sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' $SSH_CONF
            SSH_STATUS="NO"
        else
            sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' $SSH_CONF
            SSH_STATUS="YES"
        fi
        print_success "SSH Password Authentication set to: $SSH_STATUS"

        print_sub 100 "Restarting $SSH_SVC service..."
        systemctl restart "$SSH_SVC" >> "$LOG_FILE" 2>&1
        print_success "SSH service restarted"

        # ==========================================
        # Step 7: Final Verification
        # ==========================================
        show_progress "Verifying Tools and Services"
        log_separator "Final Verification"

        # ตรวจสอบคำสั่ง
        TOOLS_CHECK=(htop vim curl wget jq tar unzip ifconfig netstat)
        for cmd in "${TOOLS_CHECK[@]}"; do
            if command -v "$cmd" > /dev/null 2>&1; then
                print_success "Verified: '$cmd' is ready to use"
            else
                print_error "Missing: '$cmd' is NOT installed correctly"
            fi
        done

        # ตรวจสอบเซอร์วิส
        SVCS_CHECK=(qemu-guest-agent "$TIME_SVC" "$SSH_SVC")
        for svc in "${SVCS_CHECK[@]}"; do
            if systemctl is-active --quiet "$svc"; then
                print_success "Verified: Service '$svc' is RUNNING"
            else
                print_error "Error: Service '$svc' is NOT active"
            fi
        done

        echo -e "\n=========================================="
        echo "SUCCESS: VM Setup completed! Enjoy your system, กัปตัน."
        echo "Log file saved at: $LOG_FILE"
        echo "=========================================="
    )
    echo ""
    read -p "Press [Enter] to return to menu..." < /dev/tty
}

# ==============================================================================
# 2. SNMP Installation (install_snmp.sh)
# ==============================================================================
func_install_snmp() {
    (
        echo "========================================="
        echo "  SNMP Installation Script (Bulletproof) "
        echo "========================================="

        # 1. รับค่าจากผู้ใช้ และกรองอักขระพิเศษ (CRLF) ที่อาจติดมาจากการ Copy
        read -p "Enter SNMP Community String [default: public]: " INPUT_COMMUNITY </dev/tty
        INPUT_COMMUNITY=$(echo "$INPUT_COMMUNITY" | tr -d '\r')
        COMMUNITY_STRING=${INPUT_COMMUNITY:-public}

        SYS_LOCATION="Datacenter"
        SYS_CONTACT="admin@yourdomain.com"

        echo ""
        echo "=> Community String : $COMMUNITY_STRING"
        echo "=> Allowed IP       : Any (default)"
        echo "=> View Access      : systemonly (.1)"
        echo "========================================="
        echo "Detecting Operating System..."

        # รองรับการตรวจจับ OS รุ่นเก่า
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS=$ID
            OS_LIKE=$ID_LIKE
        elif [ -f /etc/lsb-release ]; then
            . /etc/lsb-release
            OS=$(echo $DISTRIB_ID | tr '[:upper:]' '[:lower:]')
        else
            echo "Cannot detect OS."
            exit 1
        fi

        echo "OS Detected: $OS"

        # 2. ติดตั้ง Package
        if [[ "$OS" == *"ubuntu"* || "$OS" == *"debian"* || "$OS_LIKE" == *"debian"* ]]; then
            echo "Installing SNMP on Debian/Ubuntu-based system..."
            apt-get update -y
            apt-get install -y snmpd snmp
            SVC_NAME="snmpd"
        elif [[ "$OS" == *"centos"* || "$OS" == *"rhel"* || "$OS_LIKE" == *"rhel"* ]]; then
            echo "Installing SNMP on RHEL/CentOS-based system..."
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y net-snmp net-snmp-utils
            else
                yum install -y net-snmp net-snmp-utils
            fi
            SVC_NAME="snmpd"
        else
            echo "Unsupported OS: $OS"
            exit 1
        fi

        # 3. ตั้งค่า SNMP Config
        CONF_FILE="/etc/snmp/snmpd.conf"
        echo "Configuring SNMP at $CONF_FILE..."

        # Backup ไฟล์เดิม
        if [ -f "$CONF_FILE" ]; then
            BACKUP_FILE="${CONF_FILE}.bak_$(date +%F_%H-%M-%S)"
            cp "$CONF_FILE" "$BACKUP_FILE"
            echo "Backed up original config to $BACKUP_FILE"
        fi

        # สร้างไฟล์ Config ใหม่
        echo "# SNMP Configuration generated by script" > "$CONF_FILE"
        echo "agentAddress udp:161,[::1]" >> "$CONF_FILE"
        echo "" >> "$CONF_FILE"
        echo "# --- Security & Access Control ---" >> "$CONF_FILE"
        echo "view systemonly included .1" >> "$CONF_FILE"
        echo "rocommunity $COMMUNITY_STRING default -V systemonly" >> "$CONF_FILE"
        echo "" >> "$CONF_FILE"
        echo "# --- System Information ---" >> "$CONF_FILE"
        echo "sysLocation $SYS_LOCATION" >> "$CONF_FILE"
        echo "sysContact $SYS_CONTACT" >> "$CONF_FILE"
        echo "" >> "$CONF_FILE"
        echo "# --- Logging ---" >> "$CONF_FILE"
        echo "dontLogTCPWrappersConnects yes" >> "$CONF_FILE"

        # 4. Enable และ Restart Service 
        echo "Enabling and restarting $SVC_NAME service..."

        if command -v systemctl >/dev/null 2>&1; then
            systemctl enable $SVC_NAME
            systemctl restart $SVC_NAME
            STATUS_CMD="systemctl is-active --quiet $SVC_NAME"
        else
            if command -v update-rc.d >/dev/null 2>&1; then
                update-rc.d $SVC_NAME defaults
            elif command -v chkconfig >/dev/null 2>&1; then
                chkconfig $SVC_NAME on
            fi
            service $SVC_NAME restart
            STATUS_CMD="service $SVC_NAME status"
        fi

        # 5. ตรวจสอบสถานะและทดสอบ
        if $STATUS_CMD >/dev/null 2>&1; then
            echo -e "\n✅ SNMP service installed and running successfully."
            echo "Community String: $COMMUNITY_STRING"
            echo "Port: UDP 161, [::1]:161"
            
            echo -e "\n========================================="
            echo "Running self-test: snmpwalk -v2c -c $COMMUNITY_STRING localhost .1.3.6.1.2.1.1"
            echo "========================================="
            # แก้ไขบัค Unknown Object Identifier โดยใช้เลข OID แทน
            snmpwalk -v2c -c "$COMMUNITY_STRING" localhost .1.3.6.1.2.1.1
            echo "========================================="
        else
            echo -e "\n❌ Warning: SNMP service failed to start. Please check service status."
        fi
    )
    echo ""
    read -p "Press [Enter] to return to menu..." < /dev/tty
}

# ==============================================================================
# 3. SOC Scanner (socscan.sh)
# ==============================================================================
func_socscan() {
    (
        set -e
        set -o pipefail

        cleanup() {
            echo -e "\n${YELLOW}[!] Scan interrupted. Cleaning up...${NC}"
            exit 1
        }
        trap cleanup SIGINT SIGTERM

        detect_os() {
            if [ -f /etc/os-release ]; then
                source /etc/os-release
                OS_ID=$ID
                OS_NAME=$PRETTY_NAME
            else
                OS_ID="unknown"
                OS_NAME="Unknown Linux"
            fi
        }

        malware_scan() {
            echo -e "\n${BLUE}[*] Starting Malware & Crypto Miner Scan...${NC}"
            
            local known_miners=("xmrig" "kdevtmpfsi" "kinsing" "sysupdate" "networkservice")
            echo -ne "    - Checking known miner processes... "
            local f=false
            for m in "${known_miners[@]}"; do
                if pgrep -f "$m" > /dev/null 2>&1; then
                    echo -e "\n      ${RED}[FOUND ALERT]${NC} Miner detected: $m"; f=true
                fi
            done
            [ "$f" = false ] && echo -e "${GREEN}[OK]${NC}"

            echo -ne "    - Checking /tmp for hidden executables... "
            local tmp_execs=$(find /tmp /var/tmp -maxdepth 2 -type f -executable 2>/dev/null || true)
            if [ -n "$tmp_execs" ]; then
                echo -e "\n      ${RED}[FOUND ALERT]${NC} Suspicious files found in temp dirs:"
                echo "$tmp_execs" | sed 's/^/        -> /'
            else 
                echo -e "${GREEN}[OK]${NC}"
            fi
        }

        reverse_shell_scan() {
            echo -e "\n${BLUE}[*] Starting Reverse Shell Scan...${NC}"
            
            echo -ne "    - Checking network-connected shells... "
            local rev=$(ss -tap 2>/dev/null | grep -E "bash|sh|zsh" | grep "ESTAB" || true)
            if [ -n "$rev" ]; then
                echo -e "\n      ${RED}[FOUND ALERT]${NC} Active shell connection found:"
                echo "$rev" | sed 's/^/        -> /'
            else 
                echo -e "${GREEN}[OK]${NC}"
            fi
        }

        port_scan() {
            echo -e "\n${BLUE}[*] Starting Suspicious Port Scan...${NC}"
            
            local ports=(4444 31337 1337 666 4141 8888)
            local lp=$(ss -tulnp 2>/dev/null | awk '{print $5}' | awk -F':' '{print $NF}' | sort -u)
            
            echo -ne "    - Checking commonly abused ports... "
            local f=false
            for p in "${ports[@]}"; do
                if echo "$lp" | grep -qx "$p"; then
                    if [ "$f" = false ]; then
                        echo -e "\n      ${RED}[FOUND ALERT]${NC} Suspicious ports listening:"
                        f=true
                    fi
                    
                    local service_desc="Unknown / Custom Backdoor"
                    case $p in
                        4444) service_desc="Metasploit Default / Reverse Shell" ;;
                        31337) service_desc="BackOrifice / Elite RAT" ;;
                        1337) service_desc="Generic Hacker Port / RAT" ;;
                        666) service_desc="Doom / Remote Administration Trojan" ;;
                        4141) service_desc="Metasploit / Generic Shell" ;;
                        8888) service_desc="Common Web Shell / C2 Port" ;;
                    esac
                    
                    echo -e "        -> Port $p is OPEN! (Known for: ${YELLOW}$service_desc${NC})"
                fi
            done
            [ "$f" = false ] && echo -e "${GREEN}[OK]${NC}"
        }

        user_scan() {
            echo -e "\n${BLUE}[*] Starting Privileged Users Scan...${NC}"
            
            echo -ne "    - Checking non-root UID 0 accounts... "
            local u0=$(awk -F: '($3 == "0" && $1 != "root") {print $1}' /etc/passwd)
            if [ -n "$u0" ]; then
                echo -e "\n      ${RED}[FOUND ALERT]${NC} Rogue Admin Account: $u0"
            else 
                echo -e "${GREEN}[OK]${NC}"
            fi

            echo -ne "    - Checking for empty password accounts... "
            local ep=$(awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null || true)
            if [ -n "$ep" ]; then
                echo -e "\n      ${RED}[FOUND ALERT]${NC} No password set for user: $ep"
            else 
                echo -e "${GREEN}[OK]${NC}"
            fi
        }

        persistence_scan() {
            echo -e "\n${BLUE}[*] Starting Persistence Scan...${NC}"
            
            echo -ne "    - Checking suspicious Cron jobs... "
            local c=$(grep -Erw "curl|wget|base64|bash -i" /etc/cron* /var/spool/cron 2>/dev/null || true)
            if [ -n "$c" ]; then
                echo -e "\n      ${RED}[FOUND ALERT]${NC} Cron Backdoor found:"
                echo "$c" | head -n 3 | sed 's/^/        -> /'
            else 
                echo -e "${GREEN}[OK]${NC}"
            fi
        }

        docker_scan() {
            if ! command -v docker &> /dev/null; then return; fi
            echo -e "\n${BLUE}[*] Starting Container Scan...${NC}"
            
            echo -ne "    - Checking privileged containers... "
            local p=$(docker ps -q | xargs -I {} docker inspect --format='{{.Name}}:{{.HostConfig.Privileged}}' {} | grep "true" || true)
            if [ -n "$p" ]; then 
                echo -e "\n      ${RED}[FOUND ALERT]${NC} Privileged container: $p"
            else 
                echo -e "${GREEN}[OK]${NC}"
            fi
        }

        cve_scan() {
            echo -e "\n${PURPLE}[*] Starting Targeted CVE Online Scan (via OSV API)...${NC}"
            if ! command -v curl &> /dev/null; then echo -e "    ${YELLOW}[SKIP]${NC} curl not found"; return; fi
            
            if ! timeout 2 curl -s --head https://osv.dev > /dev/null; then
                echo -e "    ${YELLOW}[SKIP]${NC} No internet access or API unreachable."; return
            fi

            local pkg="sudo"
            local ver=""
            local update_cmd=""
            local eco="Debian"
            
            if [[ "$OS_ID" == "ubuntu" ]]; then
                local os_ver=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
                eco="Ubuntu:$os_ver"
                ver=$(dpkg -s $pkg 2>/dev/null | grep Version | awk '{print $2}')
                update_cmd="apt-get update && apt-get install --only-upgrade $pkg"
            elif [[ "$OS_ID" == "debian" ]]; then
                local os_ver=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
                eco="Debian:$os_ver"
                ver=$(dpkg -s $pkg 2>/dev/null | grep Version | awk '{print $2}')
                update_cmd="apt-get update && apt-get install --only-upgrade $pkg"
            elif [[ "$OS_ID" == *"centos"* || "$OS_ID" == *"rhel"* || "$OS_ID" == *"rocky"* ]]; then
                ver=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' $pkg 2>/dev/null)
                update_cmd="yum update $pkg"
            fi

            if [ -z "$ver" ]; then echo -e "    - Could not detect $pkg version."; return; fi

            echo -ne "    - Comparing $pkg v$ver (on $eco) with latest vulnerabilities... "
            
            local payload="{\"version\": \"$ver\", \"package\": {\"name\": \"$pkg\", \"ecosystem\": \"$eco\"}}"
            if [[ "$OS_ID" == *"rhel"* || "$OS_ID" == *"centos"* ]]; then payload=$(echo "$payload" | sed 's/Debian/RPM/'); fi

            local res=$(curl -s -X POST -d "$payload" https://api.osv.dev/v1/query)
            
            if [[ "$res" == *"{}"* || -z "$res" ]]; then
                echo -e "${GREEN}[SAFE]${NC} No known CVEs found for this version."
            else
                echo -e "\n      ${RED}[VULNERABLE]${NC} Potential CVEs found for $pkg."
                
                local cves=$(echo "$res" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | sort -u | head -n 3)
                
                for cve in $cves; do
                    local block=$(echo "$res" | grep -o "\"id\":\"$cve\".*")
                    local desc=$(echo "$block" | grep -o '"summary":"[^"]*"' | head -n 1 | cut -d'"' -f4)
                    
                    if [ -z "$desc" ]; then
                        desc=$(echo "$block" | grep -o '"details":"[^"]*"' | head -n 1 | cut -d'"' -f4 | cut -c 1-80)
                        [ -n "$desc" ] && desc="${desc}..."
                    fi
                    
                    [ -z "$desc" ] && desc="No details available."
                    echo "        -> $cve: $desc"
                done
                
                echo -e "      ${GREEN}[REMEDIATION]${NC} To fix, run: ${YELLOW}sudo $update_cmd${NC}"
            fi
        }

        main() {
            detect_os
            local start_time=$(date +%s)

            echo "========================================"
            echo -e "${BLUE} SOC Scanner v20.1 (Ultimate Go-Bag)${NC}"
            echo -e " Host: ${YELLOW}$(hostname)${NC}"
            echo -e " OS:   $OS_NAME"
            echo -e " Date: $(date)"
            echo "========================================"

            malware_scan
            reverse_shell_scan
            port_scan
            user_scan
            persistence_scan
            docker_scan
            cve_scan

            local end_time=$(date +%s)
            local duration=$((end_time - start_time))

            echo -e "\n========================================"
            echo -e "${GREEN}[+] Scan Complete in $duration seconds.${NC}"
            echo "========================================"
        }

        main "$@"
    )
    echo ""
    read -p "Press [Enter] to return to menu..." < /dev/tty
}

# ==============================================================================
# 4. Health Check (health_check-v3.sh)
# ==============================================================================
func_health_check() {
    (
        TOTAL_ERRORS=0
        TOTAL_WARNINGS=0
        SUMMARY_MSG=""
        LOG_FILE="/var/log/migration_audit_$(date +%F_%H-%M).log"

        print_and_log() {
            echo -e "$1"
            echo -e "$1" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g" >> "$LOG_FILE"
        }

        check_service_exists() {
            local svc=$1
            if command -v systemctl >/dev/null 2>&1; then
                systemctl list-unit-files | grep -q "^${svc}\.service" 2>/dev/null || systemctl list-units --all | grep -q "^${svc}\.service" 2>/dev/null
                return $?
            elif [ -x "/etc/init.d/$svc" ] || [ -f "/etc/init/$svc.conf" ]; then
                return 0
            else
                return 1
            fi
        }

        check_service_active() {
            local svc=$1
            if command -v systemctl >/dev/null 2>&1; then
                systemctl is-active --quiet "$svc" 2>/dev/null
                return $?
            elif command -v service >/dev/null 2>&1; then
                service "$svc" status 2>/dev/null | grep -qiE "running|is active|start/running"
                return $?
            elif [ -x "/etc/init.d/$svc" ]; then
                /etc/init.d/"$svc" status 2>/dev/null | grep -qiE "running|is active|start/running"
                return $?
            else
                return 1
            fi
        }

        echo "Post-Migration Audit Log - $(date)" > "$LOG_FILE"
        echo "=========================================" >> "$LOG_FILE"

        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS_NAME=$NAME
            OS_ID=$ID
            OS_LIKE=$ID_LIKE
        else
            OS_NAME=$(uname -s)
            OS_ID="unknown"
        fi

        if [[ "$OS_ID" == *"ubuntu"* ]] || [[ "$OS_ID" == *"debian"* ]] || [[ "$OS_LIKE" == *"debian"* ]]; then
            OS_FAMILY="debian"
            ADMIN_GROUP="sudo"
            PKG_MGR="apt-get"
            AUTH_LOG="/var/log/auth.log"
        elif [[ "$OS_ID" == *"centos"* ]] || [[ "$OS_ID" == *"rhel"* ]] || [[ "$OS_ID" == *"rocky"* ]] || [[ "$OS_ID" == *"almalinux"* ]] || [[ "$OS_LIKE" == *"rhel"* ]]; then
            OS_FAMILY="rhel"
            ADMIN_GROUP="wheel"
            command -v dnf >/dev/null 2>&1 && PKG_MGR="dnf" || PKG_MGR="yum"
            AUTH_LOG="/var/log/secure"
        else
            OS_FAMILY="unknown"
            ADMIN_GROUP="sudo"
            AUTH_LOG="/var/log/auth.log"
        fi

        print_and_log "${CYAN}====================================================${NC}"
        print_and_log "${CYAN}   Enterprise Health Check & Audit ($OS_NAME)       ${NC}"
        print_and_log "${CYAN}====================================================${NC}"

        print_and_log "\n${YELLOW}[1] System, Load Average & Time:${NC}"
        print_and_log "OS Version: $OS_NAME"
        print_and_log "Uptime & Load: $(uptime)"
        print_and_log "Kernel: $(uname -r)"
        print_and_log "Timezone: $(date)"

        print_and_log "\n${YELLOW}[2] Storage & Inode Status:${NC}"
        print_and_log "${CYAN}>> Disk Space Usage:${NC}"
        print_and_log "$(df -hT | grep -v 'tmpfs\|cdrom\|squashfs')"
        print_and_log "${CYAN}>> Inode Usage (File Limits):${NC}"
        print_and_log "$(df -hi | grep -v 'tmpfs\|cdrom\|squashfs')"

        print_and_log "\n${YELLOW}[3] fstab Mount Verification:${NC}"
        UNMOUNTED=$(awk '!/^#/ && !/^$/ && $2 != "/" && $2 != "none" && $3 != "swap" {print $2}' /etc/fstab | while read -r mountpoint; do
            if ! mountpoint -q "$mountpoint" 2>/dev/null; then echo "$mountpoint"; fi
        done)

        if [ -z "$UNMOUNTED" ]; then
            print_and_log " ${GREEN}[OK] All fstab entries are successfully mounted.${NC}"
        else
            print_and_log " ${RED}[FAIL] The following mount points in /etc/fstab are NOT mounted:${NC}"
            for mp in $UNMOUNTED; do print_and_log "  - $mp"; done
            ((TOTAL_ERRORS++)); SUMMARY_MSG+="${RED}- Storage:${NC} Missing fstab mount points\n"
        fi

        print_and_log "\n${YELLOW}[4] Memory Usage:${NC}"
        print_and_log "$(free -m | awk '
            BEGIN { printf "  %-12s %-12s %-12s %-15s\n", "TOTAL(MB)", "USED(MB)", "FREE(MB)", "USAGE(%)" }
            NR==2 { printf "  %-12s %-12s %-12s %.2f%%\n", $2, $3, $4, $3*100/$2 }
        ')"

        print_and_log "\n${YELLOW}[5] Network & Connectivity:${NC}"
        print_and_log "Default Gateway: $(ip route | grep default | awk '{print $3}' || echo 'NOT FOUND')"
        if ping -c 1 8.8.8.8 &> /dev/null; then print_and_log "- Internet Routing: ${GREEN}[OK]${NC}"; else print_and_log "- Internet Routing: ${RED}[FAILED]${NC}"; ((TOTAL_ERRORS++)); fi
        if ping -c 1 google.com &> /dev/null; then print_and_log "- DNS Resolution: ${GREEN}[OK]${NC}"; else print_and_log "- DNS Resolution: ${RED}[FAILED]${NC}"; ((TOTAL_ERRORS++)); fi

        print_and_log "\n${YELLOW}[6] OS Patch & Update Status ($PKG_MGR):${NC}"
        print_and_log "Checking for available updates... (Please wait)"
        if [ "$OS_FAMILY" == "debian" ]; then
            timeout 15 apt-get update -qq 2>/dev/null
            UPGRADES=$(apt-get -s upgrade 2>/dev/null | grep -Po '^\d+(?= upgraded)' || echo "0")
            if [ "$UPGRADES" -eq 0 ]; then print_and_log " ${GREEN}[OK] OS is up-to-date.${NC}"; else print_and_log " ${YELLOW}[WARNING] Found $UPGRADES package(s) waiting to be updated.${NC}"; fi
        elif [ "$OS_FAMILY" == "rhel" ]; then
            UPGRADES=$($PKG_MGR check-update -q 2>/dev/null | awk 'NF' | wc -l)
            if [ "$UPGRADES" -eq 0 ]; then print_and_log " ${GREEN}[OK] OS is up-to-date.${NC}"; else print_and_log " ${YELLOW}[WARNING] Found $UPGRADES package(s) waiting to be updated.${NC}"; fi
        fi

        print_and_log "\n${YELLOW}[7] Core OS Services Health:${NC}"
        SERVICES=("sshd" "nginx" "apache2" "httpd" "mysql" "mariadb" "php-fpm")
        for service in "${SERVICES[@]}"; do
            if check_service_exists "$service"; then
                if check_service_active "$service"; then
                    print_and_log "- $service: ${GREEN}[RUNNING]${NC}"
                else
                    print_and_log "- $service: ${RED}[STOPPED/FAILED]${NC}"
                    ((TOTAL_ERRORS++)); SUMMARY_MSG+="${RED}- Service:${NC} $service is down\n"
                fi
            fi
        done

        print_and_log "\n${YELLOW}[8] Active Listening Ports & Services:${NC}"
        ss -tulpn | grep LISTEN | awk '{print $5, $7}' | while read -r address process; do
            port=$(echo "$address" | awk -F':' '{print $NF}')
            service=$(echo "$process" | awk -F'"' '{print $2}')
            [ -z "$service" ] && service="Unknown/System"
            print_and_log "- Port ${CYAN}${port}${NC}: [OPEN] by ${GREEN}${service}${NC}"
        done | sort -u -t':' -k1,1n

        print_and_log "\n${YELLOW}[9] Firewall Status:${NC}"
        if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
            print_and_log " ${GREEN}[ACTIVE] firewalld is running.${NC}"
        elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "^Status: active"; then
            print_and_log " ${GREEN}[ACTIVE] UFW is running.${NC}"
        else
            print_and_log " ${GREEN}No active ufw/firewalld found (Default Policies active).${NC}"
        fi

        print_and_log "\n${YELLOW}[10] Deep Application Discovery (Scanning for hidden/enterprise apps):${NC}"

        print_and_log "${CYAN}>> Enterprise Suites & Control Panels:${NC}"
        FOUND_ENTERPRISE=0
        if [ -d "/opt/zimbra" ] && id "zimbra" &>/dev/null; then
            print_and_log " - ${GREEN}Zimbra Collaboration Suite${NC} detected (/opt/zimbra)"
            FOUND_ENTERPRISE=1
            ZIMBRA_STATUS=$(su - zimbra -c "timeout 10 zmcontrol status" 2>/dev/null)
            if echo "$ZIMBRA_STATUS" | grep -q "Stopped"; then
                print_and_log "   ${RED}-> WARNING: Some Zimbra services are STOPPED!${NC}"
            elif echo "$ZIMBRA_STATUS" | grep -q "Running"; then
                print_and_log "   -> All Zimbra core services are ${GREEN}[RUNNING]${NC}"
            else
                print_and_log "   -> Could not determine exact Zimbra status (check manually)"
            fi
        fi
        if [ -d "/usr/local/cpanel" ]; then print_and_log " - ${GREEN}cPanel/WHM${NC} detected"; FOUND_ENTERPRISE=1; fi
        if [ -d "/usr/local/directadmin" ]; then print_and_log " - ${GREEN}DirectAdmin${NC} detected"; FOUND_ENTERPRISE=1; fi
        if [ $FOUND_ENTERPRISE -eq 0 ]; then print_and_log " - No major control panels or enterprise suites detected."; fi

        print_and_log "${CYAN}>> Third-Party Apps in /opt (Non-Standard Installations):${NC}"
        OPT_APPS=$(find /opt -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null | grep -vE "^(cni|containerd|zimbra)$")
        if [ -n "$OPT_APPS" ]; then echo "$OPT_APPS" | while read -r app; do print_and_log "   - /opt/${GREEN}$app${NC}"; done; else print_and_log " - No additional apps found in /opt."; fi

        print_and_log "${CYAN}>> Active Service Users (Running background processes):${NC}"
        ACTIVE_USERS=$(ps -eo user | sort | uniq | grep -vE "^(root|USER|syslog|daemon|messagebus|systemd|dbus|postfix|polkitd|chrony|ntp|ssh|nobody|systemd-.*)$")
        if [ -n "$ACTIVE_USERS" ]; then
            echo "$ACTIVE_USERS" | while read -r usr; do
                PROC_COUNT=$(pgrep -u "$usr" | wc -l)
                print_and_log " - User: ${YELLOW}$usr${NC} is running ${CYAN}$PROC_COUNT${NC} processes."
            done
        fi

        print_and_log "${CYAN}>> Custom Systemd Services (Manual/App Installations):${NC}"
        if command -v systemctl >/dev/null 2>&1; then
            CUSTOM_SERVICES=$(find /etc/systemd/system -maxdepth 1 -type f -name "*.service" -exec basename {} \; 2>/dev/null | grep -vE "^(multi-user|default|dbus)")
            if [ -n "$CUSTOM_SERVICES" ]; then
                for app in $CUSTOM_SERVICES; do
                    if systemctl is-active --quiet "$app" 2>/dev/null; then
                        print_and_log " - $app: ${GREEN}[RUNNING]${NC}"
                    else
                        print_and_log " - $app: ${RED}[STOPPED/FAILED]${NC}"
                    fi
                done
            else
                print_and_log " - No manual custom .service files found."
            fi
        else
            print_and_log " - ${YELLOW}System is not using systemd. Skipped custom .service scan.${NC}"
        fi

        print_and_log "${CYAN}>> Docker Containers:${NC}"
        if command -v docker >/dev/null 2>&1; then
            if check_service_active "docker" || docker info >/dev/null 2>&1; then
                DOCKER_COUNT=$(docker ps -q 2>/dev/null | wc -l)
                if [ "$DOCKER_COUNT" -gt 0 ]; then
                    print_and_log " - Found $DOCKER_COUNT running container(s):"
                    docker ps --format "   - {{.Names}} ({{.Image}})" | while read -r line; do print_and_log "$line"; done
                else
                    print_and_log " - Docker is running, but 0 active containers."
                fi
            else
                print_and_log " - Docker is installed but ${RED}[STOPPED]${NC}."
            fi
        else
            print_and_log " - Docker not active or not installed."
        fi

        print_and_log "\n${YELLOW}[11] Advanced Security Audit:${NC}"

        print_and_log "${CYAN}>> Interactive Users:${NC}"
        awk -F: '($3>=1000 || $1=="root") && $7 !~ /(nologin|false)$/ {print " - " $1}' /etc/passwd | while read -r line; do print_and_log "$line"; done

        print_and_log "${CYAN}>> SSH Key Audit (root):${NC}"
        if [ -f /root/.ssh/authorized_keys ]; then
            KEY_COUNT=$(wc -l < /root/.ssh/authorized_keys)
            print_and_log " - Found $KEY_COUNT authorized keys for root."
        else
            print_and_log " - ${GREEN}[OK] No authorized_keys found for root.${NC}"
        fi

        print_and_log "${CYAN}>> Failed Login Attempts (Brute Force Check):${NC}"
        if [ -f "$AUTH_LOG" ]; then
            FAILED_COUNT=$(grep -c "Failed password" "$AUTH_LOG" 2>/dev/null || echo "0")
            if [ "$FAILED_COUNT" -gt 50 ]; then
                print_and_log " - ${RED}[WARNING] High number of failed logins detected: $FAILED_COUNT attempts!${NC}"
                ((TOTAL_WARNINGS++))
            else
                print_and_log " - ${GREEN}[OK] Normal login behavior ($FAILED_COUNT failed attempts).${NC}"
            fi
        fi

        print_and_log "\n${CYAN}====================================================${NC}"
        print_and_log "${CYAN}                 EXECUTIVE SUMMARY                  ${NC}"
        print_and_log "${CYAN}====================================================${NC}"

        if [ $TOTAL_ERRORS -eq 0 ] && [ $TOTAL_WARNINGS -eq 0 ]; then
            print_and_log "${GREEN}[PASS] All critical systems and applications are healthy!${NC}"
        else
            print_and_log "${YELLOW}[WARNING/FAIL] Health check found $TOTAL_ERRORS critical issue(s) and $TOTAL_WARNINGS warning(s).${NC}"
            print_and_log -n "$SUMMARY_MSG"
        fi

        print_and_log "\n${CYAN}>> Report saved to: ${LOG_FILE}${NC}"
        print_and_log "${CYAN}====================================================${NC}\n"
    )
    echo ""
    read -p "Press [Enter] to return to menu..." < /dev/tty
}

# ==============================================================================
# Main Menu System
# ==============================================================================
show_menu() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}      Enterprise Master Operations Tool v4.0          ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "  ${YELLOW}1)${NC} First setup-vm"
    echo -e "  ${YELLOW}2)${NC} SNMP Install"
    echo -e "  ${YELLOW}3)${NC} Soc Scanner"
    echo -e "  ${YELLOW}4)${NC} Migration Health Check"
    echo -e ""
    echo -e "  ${RED}0)${NC} Exit"
    echo -e "${CYAN}======================================================${NC}"
}

while true; do
    show_menu
    read -p "Select an option [0-4]: " choice < /dev/tty
    echo ""
    case $choice in
        1) func_setup_vm ;;
        2) func_install_snmp ;;
        3) func_socscan ;;
        4) func_health_check ;;
        0) echo -e "${GREEN}Exiting gracefully. Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}[!] Invalid option. Please try again.${NC}"; sleep 1.5 ;;
    esac
done
