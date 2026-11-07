# homelab-stacks

Docker-Compose-Stacks für den Homelab-Host, verwaltet über **Komodo v2** per Resource Sync. Host, Komodo und die Sync
selbst richtet [homelab-komodo](https://github.com/pmoscode/homelab-komodo) mit Ansible ein.

```
stacks/<name>/compose.yaml   ein Ordner pro Stack
komodo/<name>.toml           Komodo-Ressourcen (Resource Sync liest den ganzen Ordner)
```

## Regeln

- **Infrastruktur** (Traefik, Postgres, NetBird, Gatus) hat `deploy = true`, die Sync deployt sie.
- **App-Stacks ohne `deploy = true`.** Den ersten Deploy macht der Migrations-Cutover in `homelab-komodo`, danach
  Komodo (UI oder Sync).
- Images mit fester Version, nie `latest`. Bei der Migration dieselbe Version wie im Cluster.
- Hostnamen und andere Werte je Stack stehen im `environment` der TOML (wird zur `.env` im Stack-Ordner) und werden
  in der Compose-Datei als `${VAR}` genutzt. Secrets als Komodo-Variable `[[NAME]]`, nie im Repo.

## Ingress

| Art                         | Weg                                         | Entrypoint          | TLS                                   |
|-----------------------------|---------------------------------------------|---------------------|---------------------------------------|
| **Öffentlich** `*.pmsys.dev` | Internet → Zoraxy → Traefik `:80`           | `web`               | Zoraxy (Wildcard über desec.io)       |
| **Intern** `*.apps.lan`      | LAN → Traefik `:443` (DNS `*.apps.lan` → Tiny) | `websecure`      | Traefik, Wildcard `*.apps.lan` eigene CA |

Das Zertifikat für `*.apps.lan` stellt Ansible aus (homelab-komodo, Rolle `tls_internal`) und legt es mit der
dynamischen Traefik-Config unter `/srv/traefik` ab. `http://<app>.apps.lan` leitet auf HTTPS um.

Apps hängen am externen Netzwerk `proxy` und setzen Traefik-Labels. Öffentliche App:

```yaml
services:
  app:
    networks: [proxy]
    labels:
      - traefik.enable=true
      - traefik.http.routers.app.rule=Host(`${APP_HOST}`)
      - traefik.http.routers.app.entrypoints=web
      - traefik.http.services.app.loadbalancer.server.port=8080

networks:
  proxy:
    external: true
```

Interne App: gleich, nur `entrypoints=websecure` (TLS ist dort Standard):

```yaml
      - traefik.http.routers.app.entrypoints=websecure
```

Apps mit Datenbank hängen zusätzlich am externen Netzwerk `db` (vom Stack `postgres` angelegt, intern, ohne
Internetzugang) und verbinden sich mit `postgres:5432`. Datenbank und Rolle legt die Migration an, neue Apps per
`docker exec -it postgres psql -U postgres`.

Traefik spricht die Docker-API nur über den Socket-Proxy (Netzwerk `socket_proxy`, intern, nur lesend). Andere
Dienste, die die Docker-API brauchen (z. B. Alloy), hängen sich an dasselbe Netzwerk.

## Stacks

| Stack        | Hostnamen                             | Hinweis                                                     |
|--------------|---------------------------------------|-------------------------------------------------------------|
| `traefik`    | –                                     | Port 80/443, mit Socket-Proxy, `deploy = true`              |
| `postgres`   | –                                     | Postgres 17.5 für alle Apps, Netzwerk `db`, `deploy = true` |
| `netbird`    | –                                     | Routing-Peer (NetBird Cloud) für das LAN, Host-Netzwerk, `deploy = true` |
| `zoraxy`     | `*.pmsys.dev` (öffentlich)            | auf dem UGreen-NAS (`nas-ugreen`), WAN 80/443, Wildcard per DNS-01 |
| `gatus`      | `http://<nas>:8080` (LAN)             | auf `nas-ugreen`, HTTP- und Zertifikatsprüfung aller Apps, Alarm an ntfy, `deploy = true` |
| `excalidraw` | `draw.pmsys.dev`, `ws-draw.pmsys.dev` | öffentlich, zustandslos, Collab-Server braucht eigene Route |
| `homarr`     | `home.apps.lan`                       | intern, SQLite, Secret `HOMARR_SECRET_ENCRYPTION_KEY`       |
| `trmnl`      | `trmnl.pmsys.dev`                     | öffentlich, SQLite, `APP_KEY` aus dem Image                 |
| `docmost`    | `docs.apps.lan`                       | intern, Postgres (`db`), eigenes Redis, Secrets `DOCMOST_*` |
| `pgadmin`    | `pgadmin.apps.lan`                    | intern, Netzwerk `db`, Login aus der migrierten Config-DB   |
| `navidrome`  | `music.pmsys.dev`                     | öffentlich, Musik vom NAS (`/mnt/music`, nur lesend)        |
| `audiobookshelf` | `books.pmsys.dev`                  | öffentlich, Hörbücher lokal (~90 GB), Version fest 2.35.0  |
| `toniebox-manager` | `tonie.apps.lan`                  | intern, SQLite, distroless, Secrets `TONIEBOX_*`           |
| `jdownloader` | `jd.apps.lan`                        | intern, Daten auf dem NAS (`/mnt/nas/jdownloader`)          |
| `paperless`  | `paperless.apps.lan`                  | intern, Postgres (`db`), eigenes Redis, consume auf dem NAS |
| `opencloud`  | `cloud.apps.lan`                      | intern, PosixFS auf dem NAS (`/mnt/opencloud`), eingebauter IdP |
| `vaultwarden`    | `vault.pmsys.dev`                  | öffentlich, SQLite, Admin-Token/SMTP in `config.json`      |
| `minecraft`  | `mc.apps.lan:25565`, Karte `:8080`    | intern, Fabric 26.2, lazymc startet den Server bei Bedarf, Komodo-Alarme aus |

## Komodo-Ressourcen außer Stacks

| Datei                 | Inhalt                                                                                   |
|-----------------------|------------------------------------------------------------------------------------------|
| `komodo/alerter.toml` | Alerter `ntfy`: alle Alarme als Push über ntfy.sh, Topic aus der Secret-Variable `NTFY_TOPIC` |
| `komodo/servers.toml` | Schwellen für CPU, RAM und Platte je Server. Die Server legt das Onboarding an, die Sync ändert nur die genannten Felder |

Komodo meldet CPU, RAM und Platte erst, wenn der Wert zwei Messungen hintereinander (ca. 10 s) über der Schwelle
liegt, und schließt den Alarm wieder, wenn er darunter fällt. Platten zählen nur, wenn die Periphery sie meldet
(`include_disk_mounts`, setzt homelab-komodo). Nach einem Push meldet die Sync außerdem „Pending“, bis sie läuft.

Gatus (`stacks/gatus/config/config.yaml`) prüft vom NAS aus jede App über ihren normalen Hostnamen und meldet an dasselbe
ntfy-Topic: nach drei Fehlschlägen in Folge (3 min), Entwarnung nach zwei guten. Zertifikate: öffentlich mindestens
14 Tage, `*.apps.lan` mindestens 30 Tage Restlaufzeit. Neue App: Endpoint in `config/config.yaml` ergänzen, Gatus lädt ihn nach dem Deploy von selbst.
Das nächtliche Backup (homelab-komodo, Rolle `backup`) meldet sich als externer Endpoint `backup/apps-node-1`: Alarm
bei einem Fehler oder wenn 25 h keine Meldung kommt.
