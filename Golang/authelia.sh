#!/usr/bin/env bash

# ==============================================================================
# Authelia Native Manager & Access Control Engine
# ==============================================================================

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
        "$BIN_PATH" --version 2>/dev/null | awk '{print $3}' || echo "Installed"
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
LimitNOFILE=65535
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
    [ -z "$hash" ] && { echo -e "${CLR_RED}[!] Hash calculation failed.${CLR_NC}"; return; }

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
    echo -e "${CLR_GRN}[+] User updated successfully in $USERS_FILE${CLR_NC}"
}

manage_domain_rules() {
    echo ""
    echo -e "${CLR_CYN}====================================================${CLR_NC}"
    echo -e "${CLR_CYN}       Authelia Access Control Rule Manager         ${CLR_NC}"
    echo -e "${CLR_CYN}====================================================${CLR_NC}"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${CLR_RED}[!] Configuration file not found at $CONFIG_FILE${CLR_NC}"
        return
    fi

    echo -e "${CLR_BLU}[*] Current Access Rules Preview:${CLR_NC}"
    awk '/rules:/,/^[a-z]/' "$CONFIG_FILE" | grep -E "(domain|policy)" | head -n 12
    echo "----------------------------------------------------"

    read -p " Enter Domain or Subdomain to protect (e.g. 9c.ykno.ir or *.ykno.ir): " in_dom
    [ -z "$in_dom" ] && return

    echo ""
    echo " Select Access Policy for $in_dom:"
    echo " 1) bypass     - Public access / No login required"
    echo " 2) one_factor - Password only (Recommended for standard tools)"
    echo " 3) two_factor - Password + 2FA TOTP (High Security)"
    read -p " Selection [1-3, Default: 1]: " pol_choice
    local pol="bypass"
    case $pol_choice in
        2) pol="one_factor" ;;
        3) pol="two_factor" ;;
        *) pol="bypass" ;;
    esac

    # درج قانون در ابتدای بلاک rules برای داشتن بالاترین اولویت اجرایی
    if grep -q "rules:" "$CONFIG_FILE"; then
        sed -i "/rules:/a \      - domain: \"$in_dom\"\n        policy: $pol" "$CONFIG_FILE"
        echo -e "${CLR_BLU}[*] Testing and reloading Authelia...${CLR_NC}"
        systemctl restart authelia
        echo -e "${CLR_GRN}[+] Rule successfully registered: '$in_dom' -> Policy: '$pol'${CLR_NC}"
    else
        echo -e "${CLR_RED}[!] Could not locate 'rules:' section inside $CONFIG_FILE${CLR_NC}"
    fi
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
            echo -e "${CLR_YLW}[*] No registration link found in notification file.${CLR_NC}"
        fi
    else
        echo -e "${CLR_YLW}[*] Notification file does not exist yet.${CLR_NC}"
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
    if systemctl is-active --quiet authelia; then
        echo -e " Status  : ${CLR_GRN}Active (Running)${CLR_NC}"
    elif [ -f "$SERVICE_FILE" ]; then
        echo -e " Status  : ${CLR_YLW}Stopped / Inactive${CLR_NC}"
    else
        echo -e " Status  : ${CLR_RED}Not Installed${CLR_NC}"
    fi
    echo -e " Version : ${CLR_GRN}$(get_version)${CLR_NC}"
    echo "--------------------------------------"
    if [ ! -f "$BIN_PATH" ]; then
        echo " 1) Install Authelia"
    else
        echo " 1) Update Authelia Binary"
    fi
    echo " 2) Manage Access Rules (Add/Bypass Domains)"
    echo " 3) Add or Change User Password"
    echo " 4) Get 2FA QR Code / Link"
    echo " 5) Start Service"
    echo " 6) Stop Service"
    echo " 7) Restart Service"
    echo " 8) View Status & Logs"
    echo " 9) Delete Authelia"
    echo ""
    echo -e " ${CLR_ORG}b) Back${CLR_NC}"
    echo "--------------------------------------"
    read -p " Select option [1-9, b]: " c
    case $c in
        1) 
            if [ ! -f "$BIN_PATH" ]; then
                install_authelia
            else
                systemctl stop authelia
                download_binary
                systemctl restart authelia
                echo -e "${CLR_GRN}[+] Binary updated.${CLR_NC}"
            fi
            read -p "Press Enter to continue..." ;;
        2) manage_domain_rules; read -p "Press Enter to continue..." ;;
        3) user_add_or_update; read -p "Press Enter to continue..." ;;
        4) get_registration_qr; read -p "Press Enter to continue..." ;;
        5) systemctl start authelia; echo -e "${CLR_GRN}[+] Started.${CLR_NC}"; read -p "Press Enter to continue..." ;;
        6) systemctl stop authelia; echo -e "${CLR_YLW}[*] Stopped.${CLR_NC}"; read -p "Press Enter to continue..." ;;
        7) systemctl restart authelia; echo -e "${CLR_GRN}[+] Restarted.${CLR_NC}"; read -p "Press Enter to continue..." ;;
        8) journalctl -u authelia -n 30 --no-pager; read -p "Press Enter to continue..." ;;
        9) 
            read -p " Delete Authelia completely? [y/N]: " conf
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
