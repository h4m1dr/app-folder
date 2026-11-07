#!/usr/bin/env bash

INSTALL_DIR="/opt/authelia"
BIN_PATH="/usr/local/bin/authelia"
SERVICE_FILE="/etc/systemd/system/authelia.service"
CONFIG_FILE="$INSTALL_DIR/configuration.yml"
USERS_FILE="$INSTALL_DIR/users_database.yml"
STORAGE_FILE="$INSTALL_DIR/db.sqlite3"
NOTIFY_FILE="$INSTALL_DIR/notification.txt"

CLR_RED='\033[0;31m'
CLR_GRN='\033[0;32m'
CLR_YLW='\033[1;33m'
CLR_BLU='\033[0;34m'
CLR_CYN='\033[0;36m'
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
    echo -e "${CLR_BLU}[*] Downloading latest Authelia binary...${CLR_NC}"
    local tag
    tag=$(curl -fsSL https://api.github.com/repos/authelia/authelia/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [ -z "$tag" ] && tag="v4.39.28"

    local tmp_tar="/tmp/authelia.tar.gz"
    if ! curl -fsSL "https://github.com/authelia/authelia/releases/download/${tag}/authelia-linux-amd64.tar.gz" -o "$tmp_tar"; then
        echo -e "${CLR_RED}[!] Download failed.${CLR_NC}"
        return 1
    fi

    tar -xzf "$tmp_tar" -C /tmp/
    mv /tmp/authelia-linux-amd64 "$BIN_PATH" 2>/dev/null || mv /tmp/authelia "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -f "$tmp_tar"
    echo -e "${CLR_GRN}[+] Installed to $BIN_PATH${CLR_NC}"
    return 0
}

setup_systemd() {
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Authelia Authentication Service (Native Binary)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$BIN_PATH --config $CONFIG_FILE
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable authelia >/dev/null 2>&1
}

user_add_or_update() {
    echo ""
    echo -e "${CLR_BLU}=== User Management (Argon2id) ===${CLR_NC}"
    read -p " Enter username (e.g. admin): " u_name
    [ -z "$u_name" ] && return

    read -p " Enter display name (e.g. Hamid): " u_disp
    local disp="${u_disp:-$u_name}"

    read -s -p " Enter password: " u_pass
    echo ""
    [ -z "$u_pass" ] && return

    local hash
    hash=$("$BIN_PATH" crypto hash generate argon2 --password "$u_pass" 2>/dev/null | grep 'Digest:' | awk '{print $2}')
    [ -z "$hash" ] && { echo -e "${CLR_RED}[!] Hash failed.${CLR_NC}"; return; }

    mkdir -p "$INSTALL_DIR"
    [ ! -f "$USERS_FILE" ] && echo "users:" > "$USERS_FILE"

    if grep -q "^  $u_name:" "$USERS_FILE"; then
        sed -i "/^  $u_name:/,/^    groups:/ s|^    password:.*|    password: '$hash'|" "$USERS_FILE"
    else
        cat <<U_EOF >> "$USERS_FILE"
  $u_name:
    disabled: false
    displayname: '$disp'
    password: '$hash'
    email: '${u_name}@ykno.ir'
    groups:
      - admins
U_EOF
    fi

    systemctl restart authelia 2>/dev/null
    echo -e "${CLR_GRN}[+] User updated successfully!${CLR_NC}"
}

get_registration_qr() {
    echo ""
    echo -e "${CLR_BLU}=== Two-Factor Registration Link ===${CLR_NC}"
    if [ -f "$NOTIFY_FILE" ]; then
        local link
        link=$(grep -oP 'https://[^\s]+' "$NOTIFY_FILE" | tail -n 1)
        if [ -n "$link" ]; then
            echo -e "${CLR_GRN}[+] Registration URL:${CLR_NC}"
            echo -e "${CLR_CYN}$link${CLR_NC}"
            echo ""
            echo "Open this link in your browser to scan the QR Code."
        else
            echo -e "${CLR_YLW}[*] No link in notification file yet.${CLR_NC}"
        fi
    else
        echo -e "${CLR_YLW}[*] Notification file not found.${CLR_NC}"
    fi
}

install_authelia() {
    mkdir -p "$INSTALL_DIR"
    download_binary || return
    setup_systemd
    [ ! -f "$USERS_FILE" ] && user_add_or_update
    systemctl restart authelia
    echo -e "${CLR_GRN}[+] Authelia installed & started.${CLR_NC}"
}

while true; do
    clear
    echo "======================================"
    echo "          Authelia Manager            "
    echo "======================================"
    if [ -f "$BIN_PATH" ]; then
        echo -e " Status  : ${CLR_GRN}Active (Installed)${CLR_NC}"
        echo -e " Version : ${CLR_GRN}$(get_version)${CLR_NC}"
    else
        echo -e " Status  : ${CLR_RED}Not Installed${CLR_NC}"
    fi
    echo "--------------------------------------"
    if [ ! -f "$BIN_PATH" ]; then
        echo " 1) Install Authelia"
    else
        echo " 1) Update Authelia Binary"
    fi
    echo " 2) Add or Change User Password"
    echo " 3) Get 2FA QR Code / Link"
    echo " 4) Start Service"
    echo " 5) Stop Service"
    echo " 6) Restart Service"
    echo " 7) View Status & Logs"
    echo " 8) Delete Authelia"
    echo ""
    echo -e " ${CLR_ORG}b) Back${CLR_NC}"
    echo "--------------------------------------"
    read -p " Select option: " c
    case $c in
        1) 
            if [ ! -f "$BIN_PATH" ]; then
                install_authelia
            else
                systemctl stop authelia
                download_binary
                systemctl restart authelia
                echo -e "${CLR_GRN}[+] Updated.${CLR_NC}"
            fi
            read -p "Press Enter to continue..." ;;
        2) user_add_or_update; read -p "Press Enter to continue..." ;;
        3) get_registration_qr; read -p "Press Enter to continue..." ;;
        4) systemctl start authelia; echo -e "${CLR_GRN}[+] Started.${CLR_NC}"; read -p "Press Enter to continue..." ;;
        5) systemctl stop authelia; echo -e "${CLR_YLW}[*] Stopped.${CLR_NC}"; read -p "Press Enter to continue..." ;;
        6) systemctl restart authelia; echo -e "${CLR_GRN}[+] Restarted.${CLR_NC}"; read -p "Press Enter to continue..." ;;
        7) journalctl -u authelia -n 25 --no-pager; read -p "Press Enter to continue..." ;;
        8) 
            read -p " Delete Authelia? [y/N]: " conf
            if [[ "$conf" =~ ^[yY]$ ]]; then
                systemctl stop authelia 2>/dev/null
                systemctl disable authelia 2>/dev/null
                rm -f "$SERVICE_FILE" "$BIN_PATH"
                rm -rf "$INSTALL_DIR"
                systemctl daemon-reload
                echo -e "${CLR_GRN}[+] Deleted.${CLR_NC}"
            fi
            read -p "Press Enter to continue..." ;;
        b|B) break ;;
    esac
done
