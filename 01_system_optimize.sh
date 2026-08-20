#!/bin/bash
# ==================================================================
#  SYSTEM OPTIMIZATION FOR GOOGLE CLOUD SHELL
#  Lightweight, container-safe, no systemd dependency
#  Designed for Cloud Shell (shared, limited resources)
# ==================================================================

set +e

G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
R='\033[0;31m'
NC='\033[0m'

echo -e "${C}Starting Cloud Shell optimization...${NC}"
echo ""

# ==================== 1. Update packages ====================
echo -e "${Y}[1/6] Updating package lists...${NC}"
apt-get update -qq 2>/dev/null
echo -e "${G}Done${NC}"
echo ""

# ==================== 2. Install essential tools ====================
echo -e "${Y}[2/6] Installing essential tools...${NC}"
apt-get install -y -qq curl wget jq uuid-runtime bc 2>/dev/null
echo -e "${G}Done${NC}"
echo ""

# ==================== 3. Clean package cache ====================
echo -e "${Y}[3/6] Cleaning package cache and temp files...${NC}"
apt-get autoremove -y -qq 2>/dev/null
apt-get autoclean -qq 2>/dev/null
rm -rf /var/lib/apt/lists/* 2>/dev/null
rm -rf /tmp/* 2>/dev/null
echo -e "${G}Done${NC}"
echo ""

# ==================== 4. Set directory limits (Cloud Shell home is small) ====================
echo -e "${Y}[4/6] Ensuring Xray directories exist...${NC}"
mkdir -p /usr/local/etc/xray
mkdir -p /usr/local/bin
mkdir -p /root/.local/share/xray 2>/dev/null
echo -e "${G}Done${NC}"
echo ""

# ==================== 5. Kernel params (safe best-effort) ====================
echo -e "${Y}[5/6] Applying safe kernel params (best-effort)...${NC}"

# Apply only if writable (may fail in shared container - that's OK)
sysctl -w net.core.rmem_max=16777216 2>/dev/null
sysctl -w net.core.wmem_max=16777216 2>/dev/null
sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null
sysctl -w fs.file-max=655350 2>/dev/null

# Persist to conf file (won't error if not applicable)
if [ -w /etc/sysctl.conf ]; then
    cat >> /etc/sysctl.conf << 'EOF'

# VLESS Optimization for Cloud Shell
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_fastopen = 3
fs.file-max = 655350
EOF
fi

echo -e "${Y}(Some params may not apply in shared container - normal)${NC}"
echo -e "${G}Done${NC}"
echo ""

# ==================== 6. Set system limits for user ====================
echo -e "${Y}[6/6] Setting system limits...${NC}"

# Increase nofile limit for current session
ulimit -n 65535 2>/dev/null || true

# Persist to /etc/security/limits.conf if writable
if [ -w /etc/security/limits.conf ]; then
    cat >> /etc/security/limits.conf << 'EOF'

root soft nofile 65535
root hard nofile 65535
* soft nofile 65535
* hard nofile 65535
EOF
fi

echo -e "${G}Done${NC}"
echo ""

# ==================== Summary ====================
echo -e "${G}================================================================${NC}"
echo -e "${G}  SYSTEM OPTIMIZATION COMPLETE!${NC}"
echo -e "${G}================================================================${NC}"
echo ""
echo -e "${C}Optimized:${NC}"
echo -e "   - Package lists updated"
echo -e "   - Essential tools installed (curl, jq, bc)"
echo -e "   - Package cache cleaned (frees disk space)"
echo -e "   - Kernel network params applied (best-effort)"
echo -e "   - File limits raised (up to 65535)"
echo ""
echo -e "${Y}Note: In Cloud Shell, some settings may revert if session restarts.${NC}"
echo -e "${Y}That is normal for shared containers.${NC}"
echo ""