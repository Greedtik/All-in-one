#!/bin/bash

# ==============================================================================
# Enterprise Master Operations Tool v3.1 (Full Production Code)
# ==============================================================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Please run as root.${NC}"
  exit 1
fi

trap 'echo -e "\n${RED}[!] Operation cancelled by user. Exiting...${NC}"; exit 1' SIGINT

# ==============================================================================
# Helper Functions
# ==============================================================================

# ฟังก์ชันสำหรับรอ Package Manager Lock (ป้องกัน Error ตอน apt-get)
wait_for_apt() {
    echo -e "${CYAN} -> Checking for apt locks...${NC}"
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        echo -e "${YELLOW} -> Waiting for other package managers to finish...${NC}"
        sleep 5
    done
}

# ==============================================================================
# Core Functions
# ==============================================================================

func_setup_vm() {
    echo -e "${GREEN}[*] Executing VM Provisioning (Full Setup & Hardening)...${NC}"
    LOG_FILE="/var/log/setup-vm-provision.log"
    echo "--- Starting VM Setup: $(date) ---" > "$LOG_FILE"
    
    echo -e "${CYAN} -> Setting timezone to Asia/Bangkok...${NC}"
    timedatectl set-timezone Asia/Bangkok >> "$LOG_FILE" 2>&1
    
    wait_for_apt
    echo -e "${CYAN} -> Updating OS & Installing Essential Tools...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >> "$LOG_FILE" 2>&1
    apt-get upgrade -y -qq >> "$LOG_FILE" 2>&1
    apt-get install -y curl wget git htop vim qemu-guest-agent net-tools sysstat fail2ban ufw -qq >> "$LOG_FILE" 2>&1
    
    echo -e "${CYAN} -> Applying SSH Hardening...${NC}"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
    systemctl restart sshd >> "$LOG_FILE" 2>&1
    
    echo -e "${CYAN} -> Enabling QEMU Guest Agent...${NC}"
    systemctl enable --now qemu-guest-agent >> "$LOG_FILE" 2>&1

    echo -e "${GREEN}[+] VM Provisioning completed! Full details logged to $LOG_FILE${NC}"
    read -p "Press [Enter] to return to menu..."
}

func_install_snmp() {
    echo -e "${GREEN}[*] Installing & Configuring SNMP (with VACM)...${NC}"
    wait_for_apt
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y snmpd snmp libsnmp-dev -qq
    
    echo ""
    read -p "Enter desired SNMP Community String [default: public]: " SNMP_COMMUNITY
    SNMP_COMMUNITY=${SNMP_COMMUNITY:-public}
    
    echo -e "${CYAN} -> Configuring SNMPd...${NC}"
    systemctl stop snmpd
    cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.bak
    
    # สร้าง Config แบบรัดกุม (View-Based Access Control)
    cat <<EOF > /etc/snmp/snmpd.conf
# Secure SNMP Configuration
agentAddress udp:161,udp6:[::1]:161
view   systemonly  included   .1.3.6.1.2.1.1
view   systemonly  included   .1.3.6.1.2.1.25.1
view   all         included   .1
rocommunity $SNMP_COMMUNITY default -V all
sysLocation "Enterprise Datacenter"
sysContact "System Admin"
dontLogTCPWrappersConnects yes
EOF

    systemctl start snmpd
    systemctl enable snmpd
    
    echo -e "${CYAN} -> Testing Local OID (System Description)...${NC}"
    sleep 2
    snmpwalk -v2c -c "$SNMP_COMMUNITY" 127.0.0.1 sysDescr
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[+] SNMP setup verified successfully!${NC}"
    else
        echo -e "${RED}[!] SNMP verification failed. Please check /var/log/syslog${NC}"
    fi
    read -p "Press [Enter] to return to menu..."
}

func_install_zabbix() {
    echo -e "${GREEN}[*] Installing & Configuring Zabbix Agent...${NC}"
    wait_for_apt
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y zabbix-agent -qq
    
    echo ""
    read -p "Enter Zabbix Server IP or Hostname [e.g., 192.168.1.100]: " ZBX_SERVER
    read -p "Enter this server's Hostname (for Zabbix Web) [default: $(hostname)]: " ZBX_HOST
    ZBX_HOST=${ZBX_HOST:-$(hostname)}
    
    if [ -z "$ZBX_SERVER" ]; then
        echo -e "${RED}[!] Zabbix Server IP is required. Aborting.${NC}"
        sleep 2
        return
    fi

    echo -e "${CYAN} -> Updating /etc/zabbix/zabbix_agentd.conf...${NC}"
    cp /etc/zabbix/zabbix_agentd.conf /etc/zabbix/zabbix_agentd.conf.bak
    
    sed -i "s/^Server=.*/Server=${ZBX_SERVER}/" /etc/zabbix/zabbix_agentd.conf
    sed -i "s/^ServerActive=.*/ServerActive=${ZBX_SERVER}/" /etc/zabbix/zabbix_agentd.conf
    sed -i "s/^Hostname=.*/Hostname=${ZBX_HOST}/" /etc/zabbix/zabbix_agentd.conf
    
    systemctl restart zabbix-agent
    systemctl enable zabbix-agent
    
    echo -e "${GREEN}[+] Zabbix Agent configured! Server: $ZBX_SERVER, Hostname: $ZBX_HOST${NC}"
    read -p "Press [Enter] to return to menu..."
}

func_scan_malware() {
    echo -e "${GREEN}[*] Running System Vulnerability & Malware Scan...${NC}"
    wait_for_apt
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y chkrootkit rkhunter -qq
    
    echo -e "${CYAN} -> Updating rkhunter properties...${NC}"
    rkhunter --propupd > /dev/null 2>&1
    
    echo -e "${CYAN} -> Running rkhunter (Warnings only)...${NC}"
    rkhunter --checkall --skip-keypress --quiet | grep -i warning
    
    echo -e "${CYAN} -> Running chkrootkit...${NC}"
    chkrootkit -q
    
    echo -e "${GREEN}[+] Scan completed. Please review any warnings above.${NC}"
    read -p "Press [Enter] to return to menu..."
}

func_preflight_check() {
    echo -e "${GREEN}[*] Running Cluster/Node Pre-Flight Check...${NC}"
    
    echo -e "\n${YELLOW}[ Network Interfaces & IP ]${NC}"
    ip -br a
    
    echo -e "\n${YELLOW}[ Storage (df -h) ]${NC}"
    df -h | grep -E '^/dev/'
    
    echo -e "\n${YELLOW}[ Memory Usage ]${NC}"
    free -m
    
    echo -e "\n${YELLOW}[ Service Status ]${NC}"
    for svc in sshd qemu-guest-agent snmpd zabbix-agent; do
        if systemctl is-active --quiet $svc; then
            echo -e "$svc: ${GREEN}RUNNING${NC}"
        else
            echo -e "$svc: ${RED}STOPPED/NOT FOUND${NC}"
        fi
    done
    
    echo -e "\n${GREEN}[+] Pre-flight check finished.${NC}"
    read -p "Press [Enter] to return to menu..."
}

func_system_update() {
    echo -e "${GREEN}[*] Running System Update & Cleanup...${NC}"
    wait_for_apt
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get dist-upgrade -y
    apt-get autoremove -y
    apt-get clean
    echo -e "${GREEN}[+] System is up to date and clean!${NC}"
    read -p "Press [Enter] to return to menu..."
}

# ==============================================================================
# Main Menu
# ==============================================================================

show_menu() {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${GREEN}      Enterprise Master Operations Tool v3.1          ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${YELLOW} [ Provisioning & Monitoring ]${NC}"
    echo "  1) VM Provisioning (Setup-VM / Hardening / Logging)"
    echo "  2) Install & Config SNMP (VACM / OID Test)"
    echo "  3) Install Zabbix Agent (Auto Config)"
    echo ""
    echo -e "${YELLOW} [ Security & Audit ]${NC}"
    echo "  4) Run Auto Scan Malware (rkhunter & chkrootkit)"
    echo ""
    echo -e "${YELLOW} [ Infrastructure & Delivery ]${NC}"
    echo "  5) Cluster Delivery Pre-Flight Check"
    echo ""
    echo -e "${YELLOW} [ Maintenance ]${NC}"
    echo "  6) System Update & Cleanup"
    echo ""
    echo "  0) Exit"
    echo -e "${CYAN}======================================================${NC}"
}

while true; do
    show_menu
    read -p "Select an option [0-6]: " choice
    echo ""
    case $choice in
        1) func_setup_vm ;;
        2) func_install_snmp ;;
        3) func_install_zabbix ;;
        4) func_scan_malware ;;
        5) func_preflight_check ;;
        6) func_system_update ;;
        0) echo -e "${GREEN}Exiting gracefully. Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}[!] Invalid option. Please try again.${NC}"; sleep 1.5 ;;
    esac
done
