#!/bin/bash
# =============================================================================
# start-free5gc.sh — Démarrage ordonné de free5GC v4.0.1
# =============================================================================
set -e

FREE5GC=/home/student/free5gc-local
LOG_DIR=$FREE5GC/logs
mkdir -p $LOG_DIR

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Charger le module gtp5g
info "Chargement du module gtp5g..."
cd /opt/gtp5g && sudo make -j$(nproc) && sudo make install 2>/dev/null || true
sudo modprobe gtp5g 2>/dev/null || true
lsmod | grep -q gtp5g && ok "gtp5g chargé" || warn "gtp5g non chargé (peut causer des problèmes UPF)"

# Loopback IPs pour les NFs
info "Configuration des IPs loopback..."
for ip in 127.0.0.2 127.0.0.3 127.0.0.4 127.0.0.7 127.0.0.8 \
          127.0.0.9 127.0.0.10 127.0.0.18 127.0.0.31; do
    sudo ip addr add ${ip}/8 dev lo 2>/dev/null || true
done
ok "IPs loopback configurées"

export PATH=$PATH:/usr/local/go/bin

cd $FREE5GC

info "Démarrage des Network Functions..."

# NRF en premier (registry central)
./bin/nrf -c config/nrfcfg.yaml > $LOG_DIR/nrf.log 2>&1 &
NRF_PID=$!
sleep 2
ok "NRF démarré (PID $NRF_PID)"

# Infrastructure NFs
for nf in udr udm ausf nssf; do
    ./bin/$nf -c config/${nf}cfg.yaml > $LOG_DIR/${nf}.log 2>&1 &
    sleep 1
    ok "$nf démarré"
done

# PCF
./bin/pcf -c config/pcfcfg.yaml > $LOG_DIR/pcf.log 2>&1 &
sleep 1
ok "PCF démarré"

# AMF (écoute sur 127.0.0.18:38412 pour NGAP)
./bin/amf -c config/amfcfg.yaml > $LOG_DIR/amf.log 2>&1 &
AMF_PID=$!
sleep 2
ok "AMF démarré (PID $AMF_PID)"

# SMF
./bin/smf -c config/smfcfg.yaml -u config/uerouting.yaml > $LOG_DIR/smf.log 2>&1 &
sleep 2
ok "SMF démarré"

# UPF (nécessite gtp5g + privileges root)
sudo ./bin/upf -c config/upfcfg.yaml > $LOG_DIR/upf.log 2>&1 &
sleep 3
ok "UPF démarré"

# Webconsole (optionnel)
./bin/webconsole -c config/webuicfg.yaml > $LOG_DIR/webconsole.log 2>&1 &
sleep 2

echo ""
ok "=== free5GC démarré ==="
info "Logs dans : $LOG_DIR/"
info "Webconsole : http://$(hostname -I | awk '{print $1}'):5000"
info "  Login: admin / free5gc"
echo ""

# Provisionnement automatique des abonnés
sleep 3
info "Provisionnement des abonnés MongoDB..."
bash /home/student/free5gc-local/scripts/register-ues.sh
echo ""
info "free5GC est prêt. Lance UERANSIM avec :"
info "  sudo bash /home/student/ueransim-configs/multi-ue.sh"
