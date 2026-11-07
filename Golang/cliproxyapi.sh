#!/usr/bin/env bash

# ==============================================================================
# CLIProxyAPI Management Script (Modular & Systemd Managed)
# Compatible with GolangEasy / Standalone Execution
# ==============================================================================

INSTALL_DIR="/opt/cliproxyapi"
BIN_PATH="/usr/local/bin/cliproxyapi"
SERVICE_FILE="/etc/systemd/system/cliproxyapi.service"
CONFIG_FILE="$INSTALL_DIR/config.yaml"

CLR_RED='\033[0;31m'
CLR_GRN='\033[0;32m'
CLR_YLW='\033[1;33m'
CLR_BLU='\033[0;34m'
CLR_CYN='\033[0;36m'
CLR_ORG='\033[38;5;208m'
CLR_MUTED='\033[90m'
CLR_NC='\033[0m'

get_version() {
    if [ -x "$BIN_PATH" ]; then
        "$BIN_PATH" -h 2>&1 | grep -i "Version:" | awk '{print $2}' | tr -d ',' || echo "Installed"
    else
        echo "Not Installed"
    fi
}

download_binary() {
    echo -e "${CLR_BLU}[*] Checking latest release of CLIProxyAPI...${CLR_NC}"
    local tmp_dir="/tmp/cliproxy_pkg"
    local tmp_tar="/tmp/cliproxyapi.tar.gz"
    rm -rf "$tmp_dir" "$tmp_tar"
    mkdir -p "$tmp_dir"

    local download_url
    download_url=$(curl -fsSL https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest | grep "browser_download_url.*linux.*amd64.tar.gz" | cut -d '"' -f 4 | head -n 1)

    if [ -z "$download_url" ]; then
        download_url="https://github.com/router-for-me/CLIProxyAPI/releases/latest/download/CLIProxyAPI_linux_amd64.tar.gz"
    fi

    echo -e "${CLR_BLU}[*] Downloading binary archive...${CLR_NC}"
    if ! curl -fL "$download_url" -o "$tmp_tar"; then
        echo -e "${CLR_RED}[!] Download failed. Check your internet connection or proxy.${CLR_NC}"
        rm -rf "$tmp_dir" "$tmp_tar"
        return 1
    fi

    tar -xzf "$tmp_tar" -C "$tmp_dir"

    local bin_source
    bin_source=$(find "$tmp_dir" -maxdepth 2 -type f -exec file {} + | grep "ELF 64-bit" | cut -d: -f1 | head -n 1)

    if [ -n "$bin_source" ] && [ -f "$bin_source" ]; then
        mv "$bin_source" "$BIN_PATH"
        chmod +x "$BIN_PATH"
        rm -rf "$tmp_dir" "$tmp_tar"
        echo -e "${CLR_GRN}[+] Binary installed successfully to $BIN_PATH${CLR_NC}"
        return 0
    else
        echo -e "${CLR_RED}[!] Failed to locate valid ELF executable inside archive.${CLR_NC}"
        rm -rf "$tmp_dir" "$tmp_tar"
        return 1
    fi
}

setup_systemd() {
    local mem_limit="$1"
    local cpu_limit="$2"

    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=CLIProxyAPI LLM Proxy Gateway
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$BIN_PATH -config $CONFIG_FILE
Restart=always
RestartSec=3
LimitNOFILE=65535

# Resource Security & Isolation
MemoryMax=$mem_limit
CPUQuota=$cpu_limit

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable cliproxyapi >/dev/null 2>&1
}

install_wizard() {
    mkdir -p "$INSTALL_DIR"

    download_binary || return 1

    echo ""
    echo -e "${CLR_CYN}====================================================${CLR_NC}"
    echo -e "${CLR_CYN}     Phase 1: Basic Server Configuration            ${CLR_NC}"
    echo -e "${CLR_CYN}====================================================${CLR_NC}"
    read -p " Listening Host IP [Default: 127.0.0.1]: " in_host
    local host="${in_host:-127.0.0.1}"

    read -p " Listening Port [Default: 8085]: " in_port
    local port="${in_port:-8085}"

    read -p " Admin Auth Secret Key [Default: admin123456]: " in_key
    local key="${in_key:-admin123456}"

    echo ""
    echo -e "${CLR_CYN}====================================================${CLR_NC}"
    echo -e "${CLR_CYN}     Phase 2: Advanced Application Settings         ${CLR_NC}"
    echo -e "${CLR_CYN}====================================================${CLR_NC}"
    echo " Select Log Level:"
    echo " 1) info (Default)"
    echo " 2) debug (Verbose)"
    echo " 3) warn"
    echo " 4) error"
    read -p " Selection [1-4, Default: 1]: " in_log
    local log_level="info"
    case $in_log in
        2) log_level="debug" ;;
        3) log_level="warn" ;;
        4) log_level="error" ;;
        *) log_level="info" ;;
    esac

    cat <<EOF > "$CONFIG_FILE"
host: "$host"
port: $port
auth_key: "$key"
log_level: "$log_level"
EOF

    echo ""
    echo -e "${CLR_CYN}====================================================${CLR_NC}"
    echo -e "${CLR_CYN}     Phase 3: System Resource Control & Limits      ${CLR_NC}"
    echo -e "${CLR_CYN}====================================================${CLR_NC}"
    read -p " Maximum Memory Limit (e.g. 256M, 512M, 1G) [Default: 256M]: " in_mem
    local mem_limit="${in_mem:-256M}"

    read -p " CPU Quota percentage (e.g. 50%, 100%, 150%) [Default: 100%]: " in_cpu
    local cpu_limit="${in_cpu:-100%}"

    setup_systemd "$mem_limit" "$cpu_limit"
    systemctl restart cliproxyapi

    echo ""
    echo -e "${CLR_GRN}[+] CLIProxyAPI service successfully deployed and running!${CLR_NC}"
    echo -e " Endpoint: ${CLR_YLW}http://$host:$port${CLR_NC}"
    echo -e " Config  : ${CLR_MUTED}$CONFIG_FILE${CLR_NC}"
    echo -e " Service : ${CLR_MUTED}$SERVICE_FILE${CLR_NC}"
}

edit_config() {
    local editor="${EDITOR:-nano}"
    if [ -f "$CONFIG_FILE" ]; then
        $editor "$CONFIG_FILE"
        read -p "Restart CLIProxyAPI to apply changes? [Y/n]: " ans
        if [[ ! "$ans" =~ ^[nN]$ ]]; then
            systemctl restart cliproxyapi
            echo -e "${CLR_GRN}[+] Service restarted.${CLR_NC}"
        fi
    else
        echo -e "${CLR_RED}[!] Config file not found at $CONFIG_FILE${CLR_NC}"
    fi
}

edit_service() {
    local editor="${EDITOR:-nano}"
    if [ -f "$SERVICE_FILE" ]; then
        $editor "$SERVICE_FILE"
        systemctl daemon-reload
        read -p "Restart CLIProxyAPI to apply systemd changes? [Y/n]: " ans
        if [[ ! "$ans" =~ ^[nN]$ ]]; then
            systemctl restart cliproxyapi
            echo -e "${CLR_GRN}[+] Service reloaded and restarted.${CLR_NC}"
        fi
    else
        echo -e "${CLR_RED}[!] Service file not found at $SERVICE_FILE${CLR_NC}"
    fi
}

while true; do
    clear
    echo -e "${CLR_CYN}======================================================${CLR_NC}"
    echo -e "${CLR_CYN}            CLIProxyAPI Core Control Panel            ${CLR_NC}"
    echo -e "${CLR_CYN}======================================================${CLR_NC}"
    if systemctl is-active --quiet cliproxyapi; then
        echo -e " Service Status : ${CLR_GRN}Active (Running)${CLR_NC}"
    elif [ -f "$SERVICE_FILE" ]; then
        echo -e " Service Status : ${CLR_YLW}Inactive (Stopped)${CLR_NC}"
    else
        echo -e " Service Status : ${CLR_RED}Not Installed${CLR_NC}"
    fi

    echo -e " Core Version   : ${CLR_GRN}$(get_version)${CLR_NC}"
    if [ -f "$CONFIG_FILE" ]; then
        curr_port=$(grep "port:" "$CONFIG_FILE" | head -n1 | awk '{print $2}')
        echo -e " Active Port    : ${CLR_YLW}${curr_port:-Unknown}${CLR_NC}"
    fi
    echo -e "${CLR_CYN}------------------------------------------------------${CLR_NC}"
    if [ ! -f "$BIN_PATH" ]; then
        echo " 1) Install CLIProxyAPI (Wizard Setup)"
    else
        echo " 1) Update / Re-configure CLIProxyAPI"
    fi
    echo " 2) Start Service"
    echo " 3) Stop Service"
    echo " 4) Restart Service"
    echo " 5) View Real-Time Status & Logs"
    echo " 6) Edit Application Config (config.yaml)"
    echo " 7) Edit Systemd Service & Limits (cliproxyapi.service)"
    echo " 8) Uninstall & Delete Everything"
    echo ""
    echo -e " ${CLR_ORG}b) Back${CLR_NC}"
    echo -e "${CLR_CYN}------------------------------------------------------${CLR_NC}"
    read -p " Select an option [1-8, b]: " opt
    case $opt in
        1)
            install_wizard
            read -p "Press Enter to return to menu..." ;;
        2)
            systemctl start cliproxyapi
            echo -e "${CLR_GRN}[+] Service started.${CLR_NC}"
            read -p "Press Enter to continue..." ;;
        3)
            systemctl stop cliproxyapi
            echo -e "${CLR_YLW}[*] Service stopped.${CLR_NC}"
            read -p "Press Enter to continue..." ;;
        4)
            systemctl restart cliproxyapi
            echo -e "${CLR_GRN}[+] Service restarted.${CLR_NC}"
            read -p "Press Enter to continue..." ;;
        5)
            echo -e "${CLR_BLU}[*] Displaying last 30 log entries (Press Ctrl+C to exit log viewer)...${CLR_NC}"
            journalctl -u cliproxyapi -n 30 -f --no-pager
            read -p "Press Enter to continue..." ;;
        6)
            edit_config
            read -p "Press Enter to continue..." ;;
        7)
            edit_service
            read -p "Press Enter to continue..." ;;
        8)
            read -p " Are you sure you want to completely remove CLIProxyAPI? [y/N]: " conf
            if [[ "$conf" =~ ^[yY]$ ]]; then
                systemctl stop cliproxyapi 2>/dev/null
                systemctl disable cliproxyapi 2>/dev/null
                rm -f "$SERVICE_FILE" "$BIN_PATH"
                rm -rf "$INSTALL_DIR"
                systemctl daemon-reload
                echo -e "${CLR_GRN}[+] Successfully uninstalled CLIProxyAPI.${CLR_NC}"
            fi
            read -p "Press Enter to continue..." ;;
        b|B)
            break ;;
        *)
            echo -e "${CLR_RED}Invalid option.${CLR_NC}"
            sleep 1 ;;
    esac
done
