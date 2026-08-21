#!/bin/bash
# minimal system prep for Google Cloud Shell
# (actual optimization is unnecessary — Xray already runs light)
set +e
apt-get update -qq 2>/dev/null
apt-get install -y -qq curl jq uuid-runtime unzip 2>/dev/null
mkdir -p /usr/local/etc/xray /usr/local/bin
echo "tools ready"