#!/usr/bin/env bash

APP_NAME="Authelia"
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

CACHED_LOCAL_VER=""
CACHED_REMOTE_VER=""

if [ "$EUID" -ne 0 ]; then
    echo -e "${CLR_RED}[!] Please run as root (sudo).${CLR_NC}"
    exit 1
fi

app_init_metadata() {
    if [ -f "$BIN_PATH" ]; then
        CACHED_LOCAL_VER=$("$BIN_PATH" --version 2>/dev/null | awk '{print $3}')
        [ -z "$CACHED_LOCAL_VER" ] && CACHED_LOCAL_VER="Installed"
    else
        CACHED_LOCAL_VER="Not Installed"
    fi

    if [ -f "$BIN_PATH" ] && [ -z "$CACHED_REMOTE_VER" ]; then
        CACHED_REMOTE_VER=$(curl -fsSL https://api.github.com/repos/authelia/authelia/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    fi
}

app_is_installed() {
    [ -f "$SERVICE_FILE" ] && [ -f "$BIN_PATH" ] && return 0
    return 1
}

get_version_status() {
    [ -z "$CACHED_LOCAL_VER" ] && app_init_metadata

    if [ "$CACHED_LOCAL_VER" != "Not Installed" ]; then
        if [ -n "$CACHED_REMOTE_VER" ]; then
            if [ "$CACHED_LOCAL_VER" == "$CACHED_REMOTE_VER" ]; then
                echo -e "${CLR_GRN}$CACHED_LOCAL_VER ${CLR_MUTED}(latest)${CLR_NC}"
            else
                echo -e "${CLR_YLW}$CACHED_LOCAL_VER ${CLR_MUTED}-> ${CLR_GRN}$CACHED_REMOTE_VER${CLR_NC}"
            fi
        else
            echo -e "${CLR_GRN}$CACHED_LOCAL_VER${CLR_NC}"
        fi
    else
        echo -e "${CLR_RED}Not Installed${CLR_NC}"
    fi
}

download_binary() {
    echo -e "${CLR_BLU}[*] Fetching latest Authelia release for Linux AMD64...${CLR_NC}"
    local tag
    tag=$(curl -fsSL https://api.github.com/repos/authelia/authelia/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [ -z "$tag" ] && tag="v4.39.28"

    local download_url="https://github.com/authelia/authelia/releases/download/${tag}/authelia-linux-amd64.tar.gz"
    local tmp_tar="/tmp/authelia.tar.gz"

    if ! curl -fsSL "$download_url" -o "$tmp_tar"; then
        echo -e "${CLR_RED}[!] Download failed. Check network connectivity.${CLR_NC}"
        return 1
    fi

    tar -xzf "$tmp_tar" -C /tmp/
    mv /tmp/authelia-linux-amd64 "$BIN_PATH" 2>/dev/null || mv /tmp/authelia "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -f "$tmp_tar"
    echo -e "${CLR_GRN}[+] Binary installed to $BIN_PATH${CLR_NC}"
    return 0
}

generate_configuration() {
    local base_domain="$1"
    local portal_url="$2"
    local protected_domains="$3"
    local port="$4"
    local session_exp="$5"
    local session_inact="$6"

    mkdir -p "$INSTALL_DIR"

    # Generate random 64-char secrets if not already present
    local jwt_secret=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 48)
    local sess_secret=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 48)
    local enc_key=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)

    # Format protected domains into JSON array
    local domain_rules=""
    IFS=',' read -ra ADDR <<< "$protected_domains"
    for d in "${ADDR[@]}"; do
        local clean_d=$(echo "$d" | xargs)
        [ -n "$domain_rules" ] && domain_rules="$domain_rules, "
        domain_rules="$domain_rules\"$clean_d\""
    done

    cat <<EOF > "$CONFIG_FILE"
{
  "server": {
    "address": "tcp://0.0.0.0:$port"
  },
  "log": {
    "level": "info"
  },
  "theme": "dark",
  "default_2fa_method": "totp",
  "totp": {
    "issuer": "$base_domain"
  },
  "identity_validation": {
    "reset_password": {
      "jwt_secret": "$jwt_secret"
    }
  },
  "authentication_backend": {
    "file": {
      "path": "$USERS_FILE"
    }
  },
  "access_control": {
    "default_policy": "deny",
    "rules": [
      {
        "domain": [
          $domain_rules
        ],
        "policy": "two_factor"
      }
    ]
  },
  "session": {
    "name": "authelia_session",
    "secret": "$sess_secret",
    "remember_me": "$session_exp",
    "expiration": "$session_exp",
    "inactivity": "$session_inact",
    "cookies": [
      {
        "domain": "$base_domain",
        "authelia_url": "$portal_url",
        "remember_me": "$session_exp",
        "expiration": "$session_exp",
        "inactivity": "$session_inact"
      }
    ]
  },
  "storage": {
    "encryption_key": "$enc_key",
    "local": {
      "path": "$STORAGE_FILE"
    }
  },
  "notifier": {
    "filesystem": {
      "filename": "$NOTIFY_FILE"
    }
  }
}
EOF
}

setup_systemd_service() {
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

app_configure_wizard() {
    echo ""
    echo -e "${CLR_BLU}=== Authelia Core Configuration ===${CLR_NC}"

    echo -e " Root Domain ${CLR_MUTED}(Default: ykno.ir)${CLR_NC}:"
    read -p " > " in_domain
    local cfg_domain="${in_domain:-ykno.ir}"

    echo -e " Portal Full URL ${CLR_MUTED}(Default: https://are.$cfg_domain)${CLR_NC}:"
    read -p " > " in_portal
    local cfg_portal="${in_portal:-https://are.$cfg_domain}"

    echo -e " Protected Subdomains comma-separated ${CLR_MUTED}(Default: null.ykno.ir, 9r.ykno.ir, 9z.ykno.ir)${CLR_NC}:"
    read -p " > " in_rules
    local cfg_rules="${in_rules:-null.ykno.ir, 9r.ykno.ir, 9z.ykno.ir}"

    echo -e " Listening Port ${CLR_MUTED}(Default: 9091)${CLR_NC}:"
    read -p " > " in_port
    local cfg_port="${in_port:-9091}"

    echo -e " Session Max Expiration ${CLR_MUTED}(Default: 30d)${CLR_NC}:"
    read -p " > " in_exp
    local cfg_exp="${in_exp:-30d}"

    echo -e " Session Inactivity Timeout ${CLR_MUTED}(Default: 14d)${CLR_NC}:"
    read -p " > " in_inact
    local cfg_inact="${in_inact:-14d}"

    echo -e "${CLR_BLU}[*] Generating configuration files...${CLR_NC}"
    generate_configuration "$cfg_domain" "$cfg_portal" "$cfg_rules" "$cfg_port" "$cfg_exp" "$cfg_inact"

    echo ""
    echo -e " Do you want to manually edit configuration.yml? [y/N]:"
    read -p " > " in_edit
    if [[ "$in_edit" =~ ^[yY]([eE][sS])?$ ]]; then
        nano "$CONFIG_FILE"
    fi

    systemctl restart authelia
    sleep 2
    if systemctl is-active --quiet authelia; then
        echo -e "${CLR_GRN}[+] Authelia is running with updated configuration!${CLR_NC}"
    else
        echo -e "${CLR_RED}[!] Failed to start Authelia. Check logs.${CLR_NC}"
    fi
}

user_add_or_update() {
    echo ""
    echo -e "${CLR_BLU}=== User Management (Argon2id) ===${CLR_NC}"
    read -p " Enter username (e.g. admin): " u_name
    [ -z "$u_name" ] && { echo -e "${CLR_RED}[!] Username cannot be empty.${CLR_NC}"; return; }

    read -p " Enter display name (e.g. Hamid): " u_disp
    local disp_name="${u_disp:-$u_name}"

    read -s -p " Enter password for $u_name: " u_pass
    echo ""
    [ -z "$u_pass" ] && { echo -e "${CLR_RED}[!] Password cannot be empty.${CLR_NC}"; return; }

    echo -e "${CLR_BLU}[*] Generating secure Argon2id hash...${CLR_NC}"
    local hash_output
    hash_output=$("$BIN_PATH" crypto hash generate argon2 --password "$u_pass" 2>/dev/null | grep 'Digest:' | awk '{print $2}')

    if [ -z "$hash_output" ]; then
        echo -e "${CLR_RED}[!] Failed to hash password.${CLR_NC}"
        return
    fi

    # Create users_database.yml if missing
    if [ ! -f "$USERS_FILE" ]; then
        cat <<EOF > "$USERS_FILE"
users:
EOF
    fi

    # Check if user already exists
    if grep -q "^  $u_name:" "$USERS_FILE"; then
        echo -e "${CLR_YLW}[*] User '$u_name' exists. Updating password...${CLR_NC}"
        # Update user block
        sed -i "/^  $u_name:/,/^    groups:/ s|^    password:.*|    password: '$hash_output'|" "$USERS_FILE"
    else
        cat <<EOF >> "$USERS_FILE"
  $u_name:
    disabled: false
    displayname: '$disp_name'
    password: '$hash_output'
    email: '${u_name}@ykno.ir'
    groups:
      - admins
EOF
    fi

    systemctl restart authelia
    echo -e "${CLR_GRN}[+] User '$u_name' configured successfully!${CLR_NC}"
}

get_registration_qr() {
    echo ""
    echo -e "${CLR_BLU}=== Two-Factor Registration Link ===${CLR_NC}"
    if [ -f "$NOTIFY_FILE" ]; then
        local link
        link=$(grep -oP 'https://[^\s]+' "$NOTIFY_FILE" | tail -n 1)
        if [ -n "$link" ]; then
            echo -e "${CLR_GRN}[+] Latest Registration URL found:${CLR_NC}"
            echo -e "${CLR_CYN}$link${CLR_NC}"
            echo ""
            echo "Open this link in your browser to scan the Google Authenticator QR Code."
        else
            echo -e "${CLR_YLW}[*] Notification file exists but no link found yet.${CLR_NC}"
        fi
    else
        echo -e "${CLR_YLW}[*] No notification file found at $NOTIFY_FILE.${CLR_NC}"
        echo "Make sure to first log in via web and click 'Register Device'."
    fi
}

app_install() {
    mkdir -p "$INSTALL_DIR"
    if ! download_binary; then
        return
    fi

    app_configure_wizard
    setup_systemd_service

    if [ ! -f "$USERS_FILE" ]; then
        echo ""
        echo -e "${CLR_YLW}[*] No users database found. Let's create your first user.${CLR_NC}"
        user_add_or_update
    fi

    systemctl restart authelia
    CACHED_LOCAL_VER=""
    app_init_metadata
}

app_update() {
    if ! app_is_installed; then
        echo -e "${CLR_RED}[!] Authelia is not installed yet.${CLR_NC}"
        return
    fi

    echo -e "${CLR_BLU}[*] Updating Authelia binary...${CLR_NC}"
    systemctl stop authelia
    download_binary
    systemctl restart authelia
    CACHED_LOCAL_VER=""
    CACHED_REMOTE_VER=""
    app_init_metadata
    echo -e "${CLR_GRN}[+] Authelia updated successfully.${CLR_NC}"
}

app_status() {
    clear
    echo "======================================"
    echo "       Authelia Status & Logs         "
    echo "======================================"
    systemctl status authelia --no-pager
    echo ""
    echo -e "${CLR_BLU}[*] Recent Logs (30 lines):${CLR_NC}"
    journalctl -u authelia -n 30 --no-pager
}

app_delete() {
    echo -e "${CLR_RED}[!] Removing Authelia service and installation...${CLR_NC}"
    read -p " Are you sure you want to delete Authelia? [y/N]: " confirm
    if [[ "$confirm" =~ ^[yY]([eE][sS])?$ ]]; then
        systemctl stop authelia 2>/dev/null
        systemctl disable authelia 2>/dev/null
        rm -f "$SERVICE_FILE" "$BIN_PATH"
        systemctl daemon-reload
        rm -rf "$INSTALL_DIR"
        CACHED_LOCAL_VER=""
        echo -e "${CLR_GRN}[+] Authelia removed completely.${CLR_NC}"
    fi
}

app_menu() {
    app_init_metadata
    while true; do
        clear
        echo "======================================"
        echo "          Authelia Manager            "
        echo "======================================"
        if app_is_installed; then
            echo -e " Status  : ${CLR_GRN}Active (Installed)${CLR_NC}"
            echo -e " Version : $(get_version_status)"
            echo -e " Binary  : ${CLR_BLU}$BIN_PATH${CLR_NC}"
        else
            echo -e " Status  : ${CLR_RED}Not Installed${CLR_NC}"
        fi
        echo "--------------------------------------"
        echo " 1) Install Authelia"
        echo " 2) Update Authelia Binary"
        echo " 3) Edit Core Configuration (Domains & Limits)"
        echo " 4) Add or Change User Password"
        echo " 5) Get 2FA QR Code / Registration Link"
        echo " 6) Start Service"
        echo " 7) Stop Service"
        echo " 8) Restart Service"
        echo " 9) Status & Live Logs"
        echo " 10) Delete Authelia"
        echo ""
        echo -e " ${CLR_RED}e) Exit${CLR_NC}"
        echo "--------------------------------------"
        read -p " Select option: " choice
        case $choice in
            1) app_install; read -p "Press Enter to continue..." ;;
            2) app_update; read -p "Press Enter to continue..." ;;
            3) app_configure_wizard; read -p "Press Enter to continue..." ;;
            4) user_add_or_update; read -p "Press Enter to continue..." ;;
            5) get_registration_qr; read -p "Press Enter to continue..." ;;
            6) systemctl start authelia; echo -e "${CLR_GRN}[+] Started.${CLR_NC}"; read -p "Press Enter to continue..." ;;
            7) systemctl stop authelia; echo -e "${CLR_YLW}[*] Stopped.${CLR_NC}"; read -p "Press Enter to continue..." ;;
            8) systemctl restart authelia; echo -e "${CLR_GRN}[+] Restarted.${CLR_NC}"; read -p "Press Enter to continue..." ;;
            9) app_status; read -p "Press Enter to continue..." ;;
            10) app_delete; read -p "Press Enter to continue..." ;;
            e|E) clear; exit 0 ;;
            *) ;;
        esac
    done
}

app_menu
