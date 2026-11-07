# Zoraxy

Öffentlicher Einstieg für `*.pmsys.dev`: UniFi leitet WAN 80/443 auf das UGreen-NAS (Komodo-Server `nas-ugreen`).
Die Regeln werden in der Oberfläche gepflegt (`http://<nas>:8000`), der Stand liegt unter `${ZORAXY_DATA}` auf dem
NAS. Diese Datei hält den Sollzustand fest. Grundlage: Backup des alten Zoraxy (LXC 100, v3.3.4) vom 2026-11-07.

## Proxy-Regeln

| Host                                   | Ziel                    | Besonderheit                               |
|----------------------------------------|-------------------------|--------------------------------------------|
| `books.pmsys.dev`                      | `http://10.0.1.230:80`  | Audiobookshelf (Traefik auf apps-node-1)   |
| `draw.pmsys.dev`, `ws-draw.pmsys.dev`  | `http://10.0.1.230:80`  | Excalidraw, Alias für den Collab-Websocket |
| `music.pmsys.dev`                      | `http://10.0.1.230:80`  | Navidrome                                  |
| `trmnl.pmsys.dev`                      | `http://10.0.1.230:80`  | „Disable Chunked Transfer Encoding“ an     |
| `vault.pmsys.dev`                      | `http://10.0.1.230:80`  | Vaultwarden, Websocket an (Standard)       |
| `emby.pmsys.dev`                       | `http://nas.pm.lan:8096` | Emby auf dem OMV-NAS (10.0.1.13)          |

Entfallen: `nextcloud.pmsys.dev` (ersetzt durch OpenCloud, nur LAN), alles unter `pmsys.zone`.
Default-Site: „404 Not Found“. Kein Wildcard-Proxy auf Traefik, damit nur freigegebene Hosts öffentlich sind.

## TLS

- ACME (Let's Encrypt), E-Mail wie bisher.
- Ein Zertifikat `*.pmsys.dev` per DNS-01, Anbieter **deSEC** (Nameserver `ns1.desec.io`). Token in deSEC neu anlegen,
  nur für die Domain `pmsys.dev`, und nur in Zoraxy eintragen.
- Alle Regeln verwenden das Wildcard-Zertifikat, keine Einzelzertifikate mehr.

## Zugriff

- Regel „Default“ für alle Hosts: Länder-Blacklist `ad`, `cn`, `gb`, `in`, `nl`, `ru`, `us` (wie bisher).
- Keine Basic Auth, keine Trusted Proxies (die alte Cloudflare-Liste wird nicht genutzt, DNS ist nicht proxied).

## Umstellung

1. Stack in Komodo deployen, Oberfläche einrichten (erster Aufruf legt den Admin an).
2. Aus dem LAN testen: `curl --resolve vault.pmsys.dev:443:<nas-ip> https://vault.pmsys.dev/alive`
3. UniFi: Portweiterleitung WAN 80/443 und lokale DNS-Einträge `*.pmsys.dev` von 10.0.1.17 auf die NAS-IP.
4. `komodo/traefik.toml`: `ZORAXY_IP` auf die NAS-IP (Traefik vertraut nur dann den `X-Forwarded-*`-Headern).
5. Von außen testen (Mobilnetz), danach LXC 100 abschalten.
