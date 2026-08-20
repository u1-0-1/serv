#!/bin/bash
# ==================================================================
#  VLESS + WebSocket + TLS via Google Cloud Shell Web Preview
#  Direct connection through cloudshell.dev (no Cloudflare needed)
#  Port: 8080 internal -> 443 external (TLS by Google)
# ==================================================================

set +e

R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
NC='\033[0m'

echo -e "${C}================================================================${NC}"
echo -e "${C}|${G}  VLESS PROXY SETUP FOR GOOGLE CLOUD SHELL  ${NC}              ${C}|${NC}"
echo -e "${C}|${Y}  Direct via cloudshell.dev (no Cloudflare)  ${NC}            ${C}|${NC}"
echo -e "${C}================================================================${NC}"
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${R}Please run as root: sudo bash $0${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo -e "${C}Script directory: $SCRIPT_DIR${NC}"
echo ""

# ==================== Step 1: Install tools ====================
echo -e "${Y}Step 1/4: Installing essential tools...${NC}"
apt-get update -qq 2>/dev/null
apt-get install -y -qq curl wget jq uuid-runtime bc net-tools 2>/dev/null
echo -e "${G}Tools installed${NC}"
echo ""

# ==================== Step 2: Install Xray ====================
echo -e "${Y}Step 2/4: Installing Xray Core...${NC}"

# Try official install first
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>/dev/null

# Check if installed
if [ ! -x /usr/local/bin/xray ]; then
    echo -e "${Y}Official install failed, trying direct download...${NC}"
    
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)  XRAY_ARCH="Xray-linux-64" ;;
        aarch64|arm64) XRAY_ARCH="Xray-linux-arm64-v8a" ;;
        *) echo -e "${R}Unsupported architecture${NC}"; exit 1 ;;
    esac

    XRAY_VER=$(curl -sL https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name 2>/dev/null || echo "v25.8.25")
    echo -e "  Downloading Xray ${XRAY_VER}..."
    
    cd /tmp
    curl -sL -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/${XRAY_ARCH}.zip"
    apt-get install -y -qq unzip 2>/dev/null
    unzip -o xray.zip -d /tmp/xray_extract
    mkdir -p /usr/local/bin
    cp /tmp/xray_extract/xray /usr/local/bin/xray
    chmod +x /usr/local/bin/xray
    rm -rf /tmp/xray.zip /tmp/xray_extract
    cd /
fi

XRAY_VER=$(/usr/local/bin/xray version 2>/dev/null | head -1 || echo "unknown")
if [ "$XRAY_VER" = "unknown" ]; then
    echo -e "${R}Xray installation FAILED!${NC}"
    exit 1
fi
echo -e "${G}Xray installed: $XRAY_VER${NC}"
echo ""

# ==================== Step 3: Create Xray config ====================
echo -e "${Y}Step 3/4: Creating Xray configuration...${NC}"

mkdir -p /usr/local/etc/xray

cat > /usr/local/etc/xray/config.json << 'XRAYCONFIG'
{
  "log": {
    "access": "none",
    "error": "none",
    "loglevel": "none",
    "dnsLog": false
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 8080,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/v2ray-ws",
          "headers": {}
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "blocked"
      }
    ]
  }
}
XRAYCONFIG

echo -e "${G}Xray config created at /usr/local/etc/xray/config.json${NC}"
echo -e "${G}Xray listening on 0.0.0.0:8080 (internal)${NC}"
echo ""

# ==================== Step 4: Start Xray ====================
echo -e "${Y}Step 4/4: Starting Xray...${NC}"

# Kill any existing xray
pkill -f "xray run" 2>/dev/null
sleep 1

# Start Xray as background process
nohup /usr/local/bin/xray run -c /usr/local/etc/xray/config.json > /tmp/xray.log 2>&1 &
sleep 2

if pgrep -f "xray run" > /dev/null; then
    echo -e "${G}Xray started successfully (PID: $(pgrep -f 'xray run' | head -1))${NC}"
else
    echo -e "${R}Xray failed to start! Check: cat /tmp/xray.log${NC}"
    cat /tmp/xray.log 2>/dev/null
fi

echo ""

# ==================== Install Panel ====================
echo -e "${Y}Installing User Panel...${NC}"

mkdir -p /usr/local/bin

if [ -f "$SCRIPT_DIR/user-panel.sh" ]; then
    cp "$SCRIPT_DIR/user-panel.sh" /usr/local/bin/user-panel.sh
    chmod +x /usr/local/bin/user-panel.sh
fi

# Create wrapper command
cat > /usr/local/bin/user-panel << 'WRAPPER'
#!/bin/bash
exec bash /usr/local/bin/user-panel.sh "$@"
WRAPPER
chmod +x /usr/local/bin/user-panel

# Ensure PATH
case ":$PATH:" in
    *":/usr/local/bin:"*) ;;
    *)
        echo 'export PATH="/usr/local/bin:$PATH"' >> /root/.bashrc
        export PATH="/usr/local/bin:$PATH"
        ;;
esac

echo -e "${G}Panel installed${NC}"
echo ""

# ==================== Summary ====================
echo -e "${G}================================================================${NC}"
echo -e "${G}  SETUP COMPLETE!${NC}"
echo -e "${G}================================================================${NC}"
echo ""
echo -e "${C}Server Status:${NC}"
echo -ne "   Xray binary: "
[ -x /usr/local/bin/xray ] && echo -e "${G}OK${NC}" || echo -e "${R}MISSING${NC}"
echo -ne "   Xray config: "
[ -f /usr/local/etc/xray/config.json ] && echo -e "${G}OK${NC}" || echo -e "${R}MISSING${NC}"
echo -ne "   Xray running: "
pgrep -f "xray run" > /dev/null && echo -e "${G}YES${NC}" || echo -e "${R}NO${NC}"
echo -ne "   user-panel:  "
[ -x /usr/local/bin/user-panel ] && echo -e "${G}OK${NC}" || echo -e "${R}MISSING${NC}"
echo ""
echo -e "${Y}IMPORTANT - You MUST do this in Cloud Shell:${NC}"
echo -e "   ${C}Web Preview -> Preview on port 8080${NC}"
echo -e "   This gives you the TLS URL: https://8080-cs-...cloudshell.dev"
echo ""
echo -e "${Y}Then run:${NC}"
echo -e "   ${G}sudo user-panel${NC}"
echo ""
