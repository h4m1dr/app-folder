#!/usr/bin/env bash

INSTALL_DIR="/opt/cliproxyapi"
BIN_PATH="/usr/local/bin/cliproxyapi"
SERVICE_FILE="/etc/systemd/system/cliproxyapi.service"
CONFIG_FILE="$INSTALL_DIR/config.yaml"

CLR_RED='\033[0;31m'
CLR_GRN='\033[0;32m'
CLR_YLW='\033[1;33m'
CLR_BLU='\033[0;34m'
CLR_ORG='\033[38;5;208m'
CLR_MUTED='\033[90m'
CLR_NC='\033[0m'

get_version() {
    if [ -f "$BIN_PATH" ]; then
        "$BIN_PATH" --version 2>/dev/null | awk '{print $3}'
    else
        echo "Not Installed"
    fi
}

download_binary() {
    echo -e "${CLR_BLU}[*] Downloading CLIProxyAPI binary...${CLR_NC}"
    local tmp_tar="/tmp/cliproxyapi.tar.gz"
    local download_url="https://github.com/router-for-me/CLIProxyAPI/releases/latest/download/CLIProxyAPI_linux_amd64.tar.gz"
    
    if ! curl -fsSL "$download_url" -o "$tmp_tar"; then
        echo -e "${CLR_RED}[!] Download failed.${CLR_NC}"
        return 1
    fi

    tar -xzf "$tmp_tar" -C /tmp/
    mv /tmp/CLIProxyAPI "$BIN_PATH" 2>/dev/null || mv /tmp/cliproxyapi "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -f "$tmp_tar"
    echo -e "${CLR_GRN}[+] Binary installed to $BIN_PATH${CLR_NC}"
    return 0
}

setup_systemd() {
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=CLIProxyAPI LLM Proxy Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$BIN_PATH -config $CONFIG_FILE
Restart=always
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable cliproxyapi >/dev/null 2>&1
}

install_cliproxyapi() {
    mkdir -p "$INSTALL_DIR"
    download_binary || return

    read -p " Enter listening Port (Default: 8080): " in_port
    local port="${in_port:-8080}"
    read -p " Enter Web Auth Key (Default: admin123456): " in_key
    local key="${in_key:-admin123456}"

    cat <<EOF > "$CONFIG_FILE"
host: "127.0.0.1"
port: $port
auth_key: "$key"
log_level: "info"
EOF

    setup_systemd
    systemctl restart cliproxyapi
    echo -e "${CLR_GRN}[+] CLIProxyAPI installed and running on port $port.${CLR_NC}"
}

while true; do
    clear
    echo "======================================"
    echo "          CLIProxyAPI Menu            "
    echo "======================================"
    if [ -f "$BIN_PATH" ]; then
        echo -e " Status  : ${CLR_GRN}Installed${CLR_NC}"
        echo -e " Version : ${CLR_GRN}$(get_version)${CLR_NC}"
    else
        echo -e " Status  : ${CLR_RED}Not Installed${CLR_NC}"
    fi
    echo "--------------------------------------"
    if [ ! -f "$BIN_PATH" ]; then
        echo " 1) Install CLIProxyAPI"
    else
        echo " 1) Update CLIProxyAPI"
    fi
    echo " 2) Start Service"
    echo " 3) Stop Service"
    echo " 4) Restart Service"
    echo " 5) View Status & Logs"
    echo " 6) Delete CLIProxyAPI"
    echo ""
    echo -e " ${CLR_ORG}b) Back${CLR_NC}"
    echo "--------------------------------------"
    read -p " Select option: " c
    case $c in
        1)
            if [ ! -f "$BIN_PATH" ]; then
                install_cliproxyapi
            else
                systemctl stop cliproxyapi
                download_binary
                systemctl restart cliproxyapi
                echo -e "${CLR_GRN}[+] Updated.${CLR_NC}"
            fi
            read -p "Press Enter to continue..." ;;
        2) systemctl start cliproxyapi; echo -e "${CLR_GRN}[+] Started.${CLR_NC}"; read -p "Press Enter to continue..." ;;
        3) systemctl stop cliproxyapi; echo -e "${CLR_YLW}[*] Stopped.${CLR_NC}"; read -p "Press Enter to continue..." ;;
        4) systemctl restart cliproxyapi; echo -e "${CLR_GRN}[+] Restarted.${CLR_NC}"; read -p "Press Enter to continue..." ;;
        5) journalctl -u cliproxyapi -n 25 --no-pager; read -p "Press Enter to continue..." ;;
        6)
            read -p " Delete CLIProxyAPI? [y/N]: " conf
            if [[ "$conf" =~ ^[yY]$ ]]; then
                systemctl stop cliproxyapi 2>/dev/null
                systemctl disable cliproxyapi 2>/dev/null
                rm -f "$SERVICE_FILE" "$BIN_PATH"
                rm -rf "$INSTALL_DIR"
                systemctl daemon-reload
                echo -e "${CLR_GRN}[+] Deleted.${CLR_NC}"
            fi
            read -p "Press Enter to continue..." ;;
        b|B) break ;;
    esac
done
