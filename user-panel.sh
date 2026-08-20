#!/bin/bash
# ==================================================================
#  USER PANEL - VLESS via Google Cloud Shell Web Preview
#  No Cloudflare, no cloudflared, no systemd dependency
#  Pure ASCII in read commands (container-safe)
# ==================================================================

set +e

CONFIG_FILE="/usr/local/etc/xray/config.json"
CLIENTS_DB="/usr/local/etc/xray/clients.db"
TUNNEL_LOG="/tmp/cloudflared_tunnel.log"
PANEL_NAME="USER"
VERSION="3.0"

# Cloud Shell Web Preview host (set manually or auto-detect)
CS_HOST="${CS_HOST:-}"

# Colors
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
M='\033[0;35m'
C='\033[0;36m'
W='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# ==================== FUNCTIONS ====================

header() {
    clear
    echo -e "${C}======================================================================${NC}"
    echo -e "${C}|${W}  ** ${BOLD}${PANEL_NAME} PANEL ${VERSION} **${NC}                                              ${C}|${NC}"
    echo -e "${C}|${Y}  VLESS + WS + TLS  |  Google Cloud Shell Direct${NC}                    ${C}|${NC}"
    echo -e "${C}======================================================================${NC}"
    echo ""
}

separator() {
    echo -e "${C}----------------------------------------------------------------------${NC}"
}

pause() {
    echo ""
    echo -e "${Y}Press ENTER to continue...${NC}"
    read dummy
}

generate_uuid() {
    /usr/local/bin/xray uuid 2>/dev/null || uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid
}

# Get Cloud Shell Web Preview host
get_cs_host() {
    # If already set, return it
    if [ -n "$CS_HOST" ]; then
        echo "$CS_HOST"
        return
    fi

    # Try to read from saved config
    if [ -f /usr/local/etc/xray/cs_host.txt ]; then
        cat /usr/local/etc/xray/cs_host.txt
        return
    fi

    # Auto-detect from environment
    local project_id=$(echo "$HOSTNAME" | sed 's/project-\([a-f0-9]*\)-.*/\1/')
    local region="europe-west1"
    
    if [ -n "$project_id" ] && [ "$project_id" != "$HOSTNAME" ]; then
        echo "8080-cs-${project_id}-default.cs-${region}-onse.cloudshell.dev"
        return
    fi

    # Fallback: ask user
    echo ""
    }

restart_xray() {
    pkill -f "xray run" 2>/dev/null
    sleep 1
    nohup /usr/local/bin/xray run -c "$CONFIG_FILE" > /tmp/xray.log 2>&1 &
    sleep 1

    if pgrep -f "xray run" > /dev/null; then
        return 0
    else
        return 1
    fi
}

xray_status() {
    if pgrep -f "xray run" > /dev/null; then
        echo "running"
    else
        echo "stopped"
    fi
}

# ==================== MENU 0: SET CLOUD SHELL HOST ====================

set_host() {
    header
    echo -e "${G}** SET CLOUD SHELL HOST **${NC}"
    separator
    echo ""
    echo -e "${C}Your Cloud Shell Web Preview URL looks like:${NC}"
    echo -e "   https://8080-cs-XXXXXX-default.cs-YYYYY-onse.cloudshell.dev"
    echo ""
    echo -e "${Y}You need to copy the FULL hostname (without https://)${NC}"
    echo -e "${Y}from your Web Preview URL.${NC}"
    echo ""
    echo -e "${C}Enter your Cloud Shell host:${NC}"
    echo -e "   (e.g: 8080-cs-580734228771-default.cs-europe-west1-onse.cloudshell.dev)"
    echo ""
    read new_host

    if [ -n "$new_host" ]; then
        # Remove https:// if user included it
        new_host="${new_host#https://}"
        new_host="${new_host#http://}"
        # Remove trailing slash
        new_host="${new_host%/}"
        
        CS_HOST="$new_host"
        mkdir -p /usr/local/etc/xray
        echo "$new_host" > /usr/local/etc/xray/cs_host.txt
        echo -e "${G}Host saved: $new_host${NC}"
        echo ""
        echo -e "${Y}How to get this URL:${NC}"
        echo -e "   1. In Cloud Shell, click 'Web Preview' icon (top right)"
        echo -e "   2. Select 'Preview on port 8080'"
        echo -e "   3. Copy the URL from the browser address bar"
        echo -e "   4. Paste the hostname here"
    else
        echo -e "${R}Host cannot be empty!${NC}"
    fi
    pause
}

# ==================== MENU 1: CREATE CLIENT ====================

create_client() {
    header
    echo -e "${G}** CREATE NEW CLIENT **${NC}"
    separator
    echo ""

    # Check if host is set
    current_host=$(get_cs_host)
    if [ -z "$current_host" ] || [ "$current_host" = "" ]; then
        echo -e "${R}Cloud Shell host is not set!${NC}"
        echo -e "${Y}Please set it first (Option 5 in main menu)${NC}"
        pause
        return
    fi

    echo -e "${C}Enter client name:${NC}"
    read client_name
    if [ -z "$client_name" ]; then
        echo -e "${R}Error: Name cannot be empty!${NC}"
        pause
        return
    fi

    if [ -f "$CLIENTS_DB" ] && grep -q "NAME:$client_name|" "$CLIENTS_DB"; then
        echo -e "${R}Error: Client name already exists!${NC}"
        pause
        return
    fi

    echo -e "${C}Enter UUID (leave empty to auto-generate):${NC}"
    read client_uuid
    if [ -z "$client_uuid" ]; then
        client_uuid=$(generate_uuid)
        echo -e "${G}Auto-generated UUID: ${Y}$client_uuid${NC}"
    fi

    echo -e "${C}Enter expiry days (leave empty for unlimited):${NC}"
    read expiry_days

    echo -e "${C}Enter data limit in GB (leave empty for unlimited):${NC}"
    read data_limit

    if [ -n "$expiry_days" ]; then
        expiry_ts=$(date -d "+$expiry_days days" +%s 2>/dev/null || date -v+${expiry_days}d +%s 2>/dev/null)
        expiry_date=$(date -d "@$expiry_ts" "+%Y-%m-%d %H:%M" 2>/dev/null || date -r "$expiry_ts" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Unknown")
    else
        expiry_ts="0"
        expiry_date="Unlimited"
    fi

    if [ -n "$data_limit" ]; then
        data_limit_bytes=$(echo "$data_limit * 1024 * 1024 * 1024" | bc 2>/dev/null || echo "0")
    else
        data_limit_bytes="0"
        data_limit="Unlimited"
    fi

    ws_path=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' "$CONFIG_FILE" 2>/dev/null || echo "/v2ray-ws")

    echo "NAME:$client_name|UUID:$client_uuid|EXPIRY:$expiry_ts|EXPIRY_HUMAN:$expiry_date|LIMIT:$data_limit_bytes|LIMIT_HUMAN:$data_limit|USED:0|CREATED:$(date +%s)|STATUS:active" >> "$CLIENTS_DB"

    tmpfile=$(mktemp)
    jq --arg uuid "$client_uuid" --arg email "$client_name" \
       '.inbounds[0].settings.clients += [{"id": $uuid, "email": $email}]' \
       "$CONFIG_FILE" > "$tmpfile" && mv "$tmpfile" "$CONFIG_FILE"

    restart_xray
    if [ $? -eq 0 ]; then
        echo -e "${G}Xray reloaded${NC}"
    else
        echo -e "${Y}Warning: Xray reload had issues${NC}"
    fi

    # Build share link using Cloud Shell host
    tunnel_host="$current_host"
    share_link="vless://${client_uuid}@${tunnel_host}:443?encryption=none&security=tls&type=ws&host=${tunnel_host}&path=${ws_path}&sni=${tunnel_host}#${PANEL_NAME}-${client_name}"

    echo ""
    separator
    echo -e "${G}** CLIENT CREATED SUCCESSFULLY! **${NC}"
    separator
    echo ""
    echo -e "${C}Name:${NC}        $client_name"
    echo -e "${C}UUID:${NC}        $client_uuid"
    echo -e "${C}Expiry:${NC}      $expiry_date"
    echo -e "${C}Data Limit:${NC}  $data_limit GB"
    echo -e "${C}Host:${NC}        $tunnel_host"
    echo -e "${C}Port:${NC}        443 (TLS by Google)"
    echo -e "${C}Path:${NC}        $ws_path"
    echo ""
    echo -e "${C}Share Link:${NC}"
    echo -e "${Y}$share_link${NC}"
    echo ""
    echo -e "${G}Copy this link and import in v2rayNG / v2rayN / NekoBox${NC}"
    echo ""

    pause
}

# ==================== MENU 2: MANAGE CLIENTS ====================

manage_clients() {
    while true; do
        header
        echo -e "${M}** CLIENT MANAGEMENT **${NC}"
        separator
        echo ""
        echo -e "${G}  D${NC} - ${Y}Delete a client${NC}"
        echo -e "${G}  M${NC} - ${Y}List all clients${NC}"
        echo -e "${G}  R${NC} - ${Y}View client details${NC}"
        echo -e "${G}  0${NC} - ${Y}Back to main menu${NC}"
        echo ""
        echo -e "${C}Select option:${NC}"
        read opt

        case "$opt" in
            [Dd]) delete_client ;;
            [Mm]) list_clients ;;
            [Rr]) view_details ;;
            0) return ;;
            *)
                echo -e "${R}Invalid option!${NC}"
                sleep 1
                ;;
        esac
    done
}

delete_client() {
    header
    echo -e "${R}** DELETE CLIENT **${NC}"
    separator
    echo ""

    if [ ! -f "$CLIENTS_DB" ] || [ ! -s "$CLIENTS_DB" ]; then
        echo -e "${Y}No clients found!${NC}"
        pause
        return
    fi

    list_clients_internal
    echo ""
    echo -e "${R}Enter client number to delete:${NC}"
    read num

    if ! echo "$num" | grep -qE '^[0-9]+$'; then
        echo -e "${R}Invalid number!${NC}"
        pause
        return
    fi

    client_line=$(sed -n "${num}p" "$CLIENTS_DB" 2>/dev/null)
    if [ -z "$client_line" ]; then
        echo -e "${R}Client not found!${NC}"
        pause
        return
    fi

    client_name=$(echo "$client_line" | sed 's/.*NAME:\([^|]*\).*/\1/')
    client_uuid=$(echo "$client_line" | sed 's/.*UUID:\([^|]*\).*/\1/')

    echo -e "${R}Are you sure you want to delete '$client_name'? (y/N):${NC}"
    read confirm
    if echo "$confirm" | grep -qi '^y$'; then
        sed -i "${num}d" "$CLIENTS_DB"

        tmpfile=$(mktemp)
        jq --arg uuid "$client_uuid" '.inbounds[0].settings.clients |= map(select(.id != $uuid))' "$CONFIG_FILE" > "$tmpfile" && mv "$tmpfile" "$CONFIG_FILE"

        restart_xray
        echo -e "${G}Client '$client_name' deleted successfully!${NC}"
    else
        echo -e "${Y}Cancelled.${NC}"
    fi
    pause
}

list_clients() {
    header
    echo -e "${M}** ALL CLIENTS **${NC}"
    separator
    echo ""
    list_clients_internal
    pause
}

list_clients_internal() {
    if [ ! -f "$CLIENTS_DB" ] || [ ! -s "$CLIENTS_DB" ]; then
        echo -e "${Y}No clients found. Create one first!${NC}"
        return
    fi

    printf "${BOLD}${C}%-4s %-20s %-15s %-15s %-10s %-10s${NC}\n" "No." "Name" "UUID" "Expiry" "Limit" "Status"
    separator

    local i=1
    while IFS= read -r line; do
        name=$(echo "$line" | sed 's/.*NAME:\([^|]*\).*/\1/')
        uuid=$(echo "$line" | sed 's/.*UUID:\([^|]*\).*/\1/')
        expiry_human=$(echo "$line" | sed 's/.*EXPIRY_HUMAN:\([^|]*\).*/\1/')
        limit_human=$(echo "$line" | sed 's/.*LIMIT_HUMAN:\([^|]*\).*/\1/')
        status=$(echo "$line" | sed 's/.*STATUS:\([^|]*\).*/\1/')

        uuid_short="${uuid:0:8}..."

        if [ "$status" = "active" ]; then
            status_str="${G}Active${NC}"
        else
            status_str="${R}Inactive${NC}"
        fi

        printf "%-4s %-20s %-15s %-15s %-10s %-10b\n" "$i" "$name" "$uuid_short" "$expiry_human" "$limit_human" "$status_str"
        i=$((i+1))
    done < "$CLIENTS_DB"
}

view_details() {
    header
    echo -e "${C}** CLIENT DETAILS **${NC}"
    separator
    echo ""

    if [ ! -f "$CLIENTS_DB" ] || [ ! -s "$CLIENTS_DB" ]; then
        echo -e "${Y}No clients found!${NC}"
        pause
        return
    fi

    list_clients_internal
    echo ""
    echo -e "${C}Enter client number to view:${NC}"
    read num

    if ! echo "$num" | grep -qE '^[0-9]+$'; then
        echo -e "${R}Invalid number!${NC}"
        pause
        return
    fi

    client_line=$(sed -n "${num}p" "$CLIENTS_DB" 2>/dev/null)
    if [ -z "$client_line" ]; then
        echo -e "${R}Client not found!${NC}"
        pause
        return
    fi

    name=$(echo "$client_line" | sed 's/.*NAME:\([^|]*\).*/\1/')
    uuid=$(echo "$client_line" | sed 's/.*UUID:\([^|]*\).*/\1/')
    expiry_human=$(echo "$client_line" | sed 's/.*EXPIRY_HUMAN:\([^|]*\).*/\1/')
    limit_human=$(echo "$client_line" | sed 's/.*LIMIT_HUMAN:\([^|]*\).*/\1/')
    used=$(echo "$client_line" | sed 's/.*USED:\([^|]*\).*/\1/')
    created=$(echo "$client_line" | sed 's/.*CREATED:\([^|]*\).*/\1/')
    status=$(echo "$client_line" | sed 's/.*STATUS:\([^|]*\).*/\1/')

    ws_path=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' "$CONFIG_FILE" 2>/dev/null || echo "/v2ray-ws")
    current_host=$(get_cs_host)

    if [ -z "$current_host" ]; then
        echo -e "${R}Cloud Shell host not set! Use option 5 first.${NC}"
        pause
        return
    fi

    share_link="vless://${uuid}@${current_host}:443?encryption=none&security=tls&type=ws&host=${current_host}&path=${ws_path}&sni=${current_host}#${PANEL_NAME}-${name}"

    echo ""
    separator
    echo -e "${G}** CLIENT DETAILS **${NC}"
    separator
    echo -e "${C}Name:${NC}           $name"
    echo -e "${C}UUID:${NC}           $uuid"
    echo -e "${C}Expiry:${NC}         $expiry_human"
    echo -e "${C}Data Limit:${NC}     $limit_human"
    echo -e "${C}Data Used:${NC}      $(echo "scale=2; $used / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0") GB"
    echo -e "${C}Created:${NC}        $(date -d "@$created" "+%Y-%m-%d" 2>/dev/null || date -r "$created" "+%Y-%m-%d" 2>/dev/null || echo "Unknown")"
    echo -e "${C}Status:${NC}         $status"
    echo ""
    echo -e "${C}Server Info:${NC}"
    echo -e "   ${C}Host:${NC} $current_host"
    echo -e "   ${C}Port:${NC} 443 (TLS by Google Cloud Shell)"
    echo -e "   ${C}Path:${NC} $ws_path"
    echo -e "   ${C}TLS:${NC}  ${G}Active (Google managed)${NC}"
    echo ""
    echo -e "${C}Share Link (copy this):${NC}"
    echo -e "${Y}$share_link${NC}"
    echo ""
    echo -e "${C}Quick Import:${NC}"
    echo -e "   v2rayNG: Copy link, Open app, '+', 'Import from Clipboard'"
    echo -e "   v2rayN:  Copy link, 'Servers', 'Import bulk URL from clipboard'"
    echo ""

    pause
}

# ==================== MENU 3: SYSTEM INFO ====================

system_info() {
    header
    echo -e "${B}** SYSTEM INFORMATION **${NC}"
    separator
    echo ""

    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "N/A")
    cpu_cores=$(nproc 2>/dev/null || echo "N/A")
    echo -e "${C}CPU:${NC}"
    echo -e "   Cores: ${Y}$cpu_cores${NC}"
    echo -e "   Usage: ${Y}${cpu_usage}%${NC}"
    echo ""

    ram_total=$(free -m | awk '/Mem:/ {print $2}' 2>/dev/null || echo "N/A")
    ram_used=$(free -m | awk '/Mem:/ {print $3}' 2>/dev/null || echo "N/A")
    ram_free=$(free -m | awk '/Mem:/ {print $7}' 2>/dev/null || echo "N/A")
    echo -e "${C}RAM:${NC}"
    echo -e "   Total: ${Y}${ram_total} MB${NC}"
    echo -e "   Used:  ${Y}${ram_used} MB${NC}"
    echo -e "   Free:  ${G}${ram_free} MB${NC}"
    echo ""

    disk_usage=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}' 2>/dev/null || echo "N/A")
    echo -e "${C}Disk:${NC}"
    echo -e "   Usage: ${Y}$disk_usage${NC}"
    echo ""

    echo -e "${C}Network:${NC}"
    echo -e "   IP: ${Y}$(curl -s ifconfig.me 2>/dev/null || echo 'N/A')${NC}"
    echo -e "   Hostname: ${Y}$(hostname)${NC}"

    current_host=$(get_cs_host)
    if [ -n "$current_host" ]; then
        echo -e "   Cloud Shell Host: ${G}$current_host${NC}"
    else
        echo -e "   Cloud Shell Host: ${R}Not set (use option 5)${NC}"
    fi
    echo ""

    xray_stat=$(xray_status)
    if [ "$xray_stat" = "running" ]; then
        echo -e "${C}Xray:${NC} ${G}Running${NC}"
    else
        echo -e "${C}Xray:${NC} ${R}Stopped${NC}"
    fi

    if [ -f "$CLIENTS_DB" ]; then
        client_count=$(wc -l < "$CLIENTS_DB")
        echo -e "${C}Active Clients:${NC} ${Y}$client_count${NC}"
    else
        echo -e "${C}Active Clients:${NC} ${Y}0${NC}"
    fi

    echo ""
    separator
    echo -e "${C}How to get Web Preview URL:${NC}"
    echo -e "   1. Click 'Web Preview' icon (top right in Cloud Shell)"
    echo -e "   2. Select 'Preview on port 8080'"
    echo -e "   3. Copy URL from browser"
    echo -e "   4. Paste hostname in option 5"
    echo ""

    pause
}

# ==================== MENU 5: RESTART XRAY ====================

restart_menu() {
    header
    echo -e "${Y}** RESTART XRAY **${NC}"
    separator
    echo ""
    echo -e "${Y}Restarting Xray...${NC}"
    restart_xray
    sleep 1

    if [ $? -eq 0 ]; then
        echo -e "${G}Xray restarted successfully!${NC}"
    else
        echo -e "${R}Xray failed to restart!${NC}"
        echo -e "${Y}Check: cat /tmp/xray.log${NC}"
    fi
    pause
}

# ==================== MAIN MENU ====================

main_menu() {
    while true; do
        header
        echo -e "${W}MAIN MENU${NC}"
        separator
        echo ""
        echo -e "${G}  1${NC} - ${Y}Create New Client${NC}"
        echo -e "${G}  2${NC} - ${Y}Manage Clients${NC}"
        echo -e "${G}  3${NC} - ${Y}System Information${NC}"
        echo -e "${G}  4${NC} - ${Y}Set Cloud Shell Host${NC}"
        echo -e "${G}  5${NC} - ${Y}Restart Xray${NC}"
        echo ""
        echo -e "${R}  0${NC} - ${R}Exit Panel${NC}"
        echo ""
        separator
        echo ""

        echo -e "${C}Enter your choice [0-5]:${NC}"
        read choice

        case "$choice" in
            1) create_client ;;
            2) manage_clients ;;
            3) system_info ;;
            4) set_host ;;
            5) restart_menu ;;
            0)
                echo ""
                echo -e "${G}Goodbye! Stay safe!${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${R}Invalid choice!${NC}"
                sleep 1
                ;;
        esac
    done
}

# ==================== INIT ====================

touch "$CLIENTS_DB" 2>/dev/null

if [ "$EUID" -ne 0 ]; then
    echo -e "${R}Please run as root: sudo bash $0${NC}"
    exit 1
fi

if [ ! -x /usr/local/bin/xray ]; then
    echo -e "${R}Xray binary not found at /usr/local/bin/xray${NC}"
    echo -e "${Y}   Please run the setup script first: bash 00_setup.sh${NC}"
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${R}Xray config not found at $CONFIG_FILE${NC}"
    echo -e "${Y}   Please run the setup script first: bash 00_setup.sh${NC}"
    exit 1
fi

main_menu
