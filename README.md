# janus-gateway — image Janus pour Ceffio

Image du **SFU Janus** utilisée par le *High Performance Backend* de Nextcloud
Talk dans [Ceffio](https://github.com/ceffio-suite/ceffio).

## Pourquoi ce dépôt

Le backend de Talk (signaling server de Strukturag) s'appuie sur **Janus** pour
transporter le média WebRTC. Le compose officiel fournit un `Dockerfile`, mais
il est fait pour un `docker compose build:` local — or un cluster k3s n'a pas de
chaîne de compilation.

Ce dépôt produit donc une **image publiée**, avec deux garanties :

- **reproductibilité** : toutes les versions sont figées (usrsctp par commit,
  libsrtp et Janus par tag). Rien ne pointe sur `master`.
- **configuration Ceffio** : plage média réduite et gestion du NAT, décrites
  plus bas.

## Image

    ghcr.io/ceffio-suite/janus-gateway:1.3.0

Cible `linux/amd64` (la VM Ceffio est en x86_64).

## Ce que la configuration change par rapport à Janus d'usine

### 1. Plage média réduite : `20000-20100`

Janus écoute par défaut sur `20000-40000`, soit **20 001 ports UDP** à ouvrir
sur le pare-feu. Pour une petite équipe, c'est inutilement large : chaque
participant consomme 1 à 2 ports, donc 100 ports couvrent des dizaines de
participants simultanés.

Réduire la plage réduit aussi la **surface exposée** — un point qui compte
quand le serveur est sur Internet.

### 2. NAT : l'IP publique est injectée au démarrage, jamais figée

Derrière le pare-feu, Janus doit annoncer une adresse que les navigateurs
peuvent joindre. S'il annonce ses adresses privées dans les candidats ICE, le
média **ne passe jamais** — c'est le piège classique du WebRTC auto-hébergé.

L'IP publique est donc passée par variable d'environnement au démarrage :

    JANUS_PUBLIC_IP=<ip-publique-du-deploiement>

**Elle n'est jamais écrite dans ce dépôt** — ni dans un fichier, ni dans un
exemple, ni dans un test. Une adresse publique est une information de
reconnaissance : elle révèle l'existence et la localisation d'une
infrastructure. Le déployeur la fournit, le dépôt ne la connaît pas.

> **Déjà pris en charge :** si `JANUS_STUN_SERVER` est défini, Janus découvre
> lui-même son adresse publique par STUN au démarrage (paquet UDP sortant, aucun
> port à ouvrir en plus) et `JANUS_PUBLIC_IP` devient inutile. Voir la section
> « Détection automatique » ci-dessous.

### 3. Certificat DTLS auto-signé, généré au démarrage

WebRTC exige un certificat pour le handshake DTLS. Un certificat auto-signé est
**normal et accepté** par les navigateurs dans ce contexte — contrairement au
TLS d'un site web, qui exige une autorité reconnue. Il est généré au premier
démarrage s'il n'existe pas.

## Variables d'environnement

| Variable | Défaut | Rôle |
|---|---|---|
| `JANUS_PUBLIC_IP` | *(vide)* | IP publique annoncée (NAT 1:1). Vide = pas de mapping. |
| `JANUS_RTP_PORT_RANGE` | `20000-20100` | Plage UDP pour le média. |
| `JANUS_DEBUG_LEVEL` | `4` | Niveau de log Janus (0-7). |
| `JANUS_STUN_SERVER` | *(vide)* | Serveur STUN optionnel. |

## Ports

    TCP 8088     API HTTP de Janus (utilisée par le signaling server)
    TCP 8188     transport WebSocket de Janus
    UDP 20000-20100  média RTP

Le port média est **configurable** — il doit correspondre à la règle NAT du
pare-feu. Ceffio l'ouvre en `20000-20100/udp` vers la VM 310.

## Construire localement

    docker buildx build --platform linux/amd64 -t janus-gateway:local .

Compilation depuis les sources (usrsctp, libsrtp, Janus) : comptez une
**dizaine de minutes** à froid, beaucoup moins avec le cache.

## Publier une nouvelle version

    git tag v1.3.0-1 && git push origin v1.3.0-1

Le workflow publie alors `ghcr.io/ceffio-suite/janus-gateway:1.3.0-1`.
Ceffio épingle ce tag dans son registre de versions — **jamais `latest`** :
un tag qui bouge rend un déploiement non reproductible.

## Mettre à jour Janus

1. changer `JANUS_VERSION` dans le `Dockerfile` (et le tag correspondant) ;
2. si la nouvelle version ajoute ou renomme des clés de configuration,
   **régénérer les fichiers `janus*.jcfg` depuis le `conf/` du tag upstream** —
   ne jamais les éditer à l'aveugle ;
3. rebâtir, tester, puis publier un nouveau tag.

## Licence

Janus Gateway est distribué sous **GPL-3.0** (voir le dépôt
[meetecho/janus-gateway](https://github.com/meetecho/janus-gateway)).

Ce dépôt ne contient que la recette de construction et la configuration — pas
le code de Janus, qui est récupéré depuis sa source officielle au moment du
build.