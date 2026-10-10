#!/bin/sh
# Entrypoint Janus pour Ceffio.
#
# Rôle : rendre Janus utilisable derrière le NAT du pare-feu, SANS figer
# l'adresse publique dans l'image.
#
# POURQUOI : Janus doit annoncer aux navigateurs une adresse qu'ils peuvent
# réellement joindre. Derrière un NAT, ses interfaces sont privées : s'il les
# annonce telles quelles dans les candidats ICE, le média ne passe jamais. La
# parade est `nat_1_1_mapping` (mapping 1:1 IP privée ↔ IP publique) — mais
# l'IP publique change selon le déploiement, donc elle ne peut pas être dans
# l'image.
#
# Variables reconnues :
#   JANUS_PUBLIC_IP     IP publique annoncée par Janus (nat_1_1_mapping).
#                       Si vide, aucun mapping n'est posé (déploiement local).
#   JANUS_DEBUG_LEVEL   Niveau de log (0-7). Défaut : 4 (warn).
#   JANUS_RTP_PORT_RANGE  Plage UDP média. Défaut : 20000-20100.
#   JANUS_STUN_SERVER   Serveur STUN : active la DÉTECTION AUTOMATIQUE de l'IP
#                       publique. C'est la voie recommandée — voir plus bas.
#   JANUS_STUN_PORT     Port du serveur STUN (défaut : 3478).
set -e

CFG=/opt/janus/etc/janus/janus.jcfg

# ---------------------------------------------------------------------------
# 1. IP publique (nat_1_1_mapping)
# ---------------------------------------------------------------------------
if [ -n "${JANUS_PUBLIC_IP:-}" ]; then
    if grep -q "^[[:space:]]*nat_1_1_mapping" "$CFG"; then
        sed -i "s|^[[:space:]]*nat_1_1_mapping.*|nat_1_1_mapping = \"${JANUS_PUBLIC_IP}\"|" "$CFG"
    else
        # insérer juste après l'ouverture du bloc nat {
        sed -i "/^nat: {/a\\\tnat_1_1_mapping = \"${JANUS_PUBLIC_IP}\"" "$CFG"
    fi
    echo "janus: nat_1_1_mapping = ${JANUS_PUBLIC_IP}"
else
    echo "janus: pas de JANUS_PUBLIC_IP — aucun mapping NAT (déploiement local)"
fi

# ---------------------------------------------------------------------------
# 2. Niveau de log
# ---------------------------------------------------------------------------
if [ -n "${JANUS_DEBUG_LEVEL:-}" ]; then
    sed -i "s|^[[:space:]]*debug_level.*|debug_level = ${JANUS_DEBUG_LEVEL}|" "$CFG"
fi

# ---------------------------------------------------------------------------
# 3. Plage média
# ---------------------------------------------------------------------------
if [ -n "${JANUS_RTP_PORT_RANGE:-}" ]; then
    sed -i "s|^[[:space:]]*rtp_port_range.*|rtp_port_range = \"${JANUS_RTP_PORT_RANGE}\"|" "$CFG"
    echo "janus: rtp_port_range = ${JANUS_RTP_PORT_RANGE}"
fi

# ---------------------------------------------------------------------------
# 4. Serveur STUN — DÉTECTION AUTOMATIQUE DE L'IP PUBLIQUE
#
# POURQUOI C'EST PRÉFÉRABLE À JANUS_PUBLIC_IP : une variable qu'il faut
# connaître AVANT de déployer est un obstacle pour un produit auto-portant.
# Janus sait faire mieux : au démarrage, si un serveur STUN est configuré, il
# envoie un vrai paquet STUN en UDP, lit le XOR-MAPPED-ADDRESS de la réponse, et
# appelle janus_add_public_ip() avec le résultat (src/ice.c) — la MÊME fonction
# que celle utilisée par nat_1_1_mapping. L'IP publique est donc découverte
# seule, sans aucun port supplémentaire à ouvrir : le paquet sort par le NAT,
# sur un port source éphémère (ou sur la plage média, déjà ouverte).
#
# Vérifié dans le code source de Janus 1.3.0, puis en exécution réelle.
# ---------------------------------------------------------------------------
if [ -n "${JANUS_STUN_SERVER:-}" ]; then
    STUN_PORT="${JANUS_STUN_PORT:-3478}"
    if grep -qE "^[[:space:]]*stun_server" "$CFG"; then
        sed -i "s|^[[:space:]]*stun_server.*|stun_server = \"${JANUS_STUN_SERVER}\"|" "$CFG"
    else
        sed -i "/^nat: {/a\\\tstun_server = \"${JANUS_STUN_SERVER}\"" "$CFG"
    fi
    if grep -qE "^[[:space:]]*stun_port" "$CFG"; then
        sed -i "s|^[[:space:]]*stun_port.*|stun_port = ${STUN_PORT}|" "$CFG"
    else
        sed -i "/^[[:space:]]*stun_server/a\\\tstun_port = ${STUN_PORT}" "$CFG"
    fi
    echo "janus: stun_server = ${JANUS_STUN_SERVER}:${STUN_PORT} (détection auto de l'IP publique)"
fi

# ---------------------------------------------------------------------------
# 5. Certificats auto-signés pour DTLS
#
# Janus a besoin d'un certificat pour DTLS (le handshake de WebRTC). Le
# certificat fourni par l'image est auto-signé, ce qui est normal et accepté
# par les navigateurs pour DTLS — contrairement au TLS des sites web.
# On ne le régénère que s'il est absent.
# ---------------------------------------------------------------------------
CERTDIR=/opt/janus/share/janus/certs
if [ ! -f "$CERTDIR/mycert.pem" ]; then
    # Le certificat est normalement créé au build. On n'arrive ici que si le
    # répertoire a été remplacé (volume monté par-dessus, par exemple).
    # NE PAS laisser échouer : sans certificat Janus démarre mais le DTLS
    # échoue, et une erreur de démarrage serait plus trompeuse qu'utile.
    echo "janus: certificat absent, génération"
    mkdir -p "$CERTDIR" 2>/dev/null || true
    if openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
        -keyout "$CERTDIR/mykey.pem" -out "$CERTDIR/mycert.pem" \
        -subj "/CN=janus" >/dev/null 2>&1; then
        cat "$CERTDIR/mycert.pem" > "$CERTDIR/mycert-fullchain.pem"
        : > "$CERTDIR/mycacert.pem"
    else
        echo "janus: AVERTISSEMENT — certificat DTLS non généré (répertoire non inscriptible ?)" >&2
    fi
fi

echo "janus: démarrage — $*"
exec "$@"