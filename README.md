# homelab-stacks

Docker-Compose-Stacks für den Homelab-Host, verwaltet über **Komodo v2** per Resource Sync. Host, Komodo und die Sync
selbst richtet [homelab-komodo](https://github.com/pmoscode/homelab-komodo) mit Ansible ein.

```
stacks/<name>/compose.yaml   ein Ordner pro Stack
komodo/<name>.toml           Komodo-Ressourcen (Resource Sync liest den ganzen Ordner)
```

## Regeln

- **Infrastruktur** (Traefik, Postgres, Monitoring) hat `deploy = true`, die Sync deployt sie.
- **App-Stacks ohne `deploy = true`.** Den ersten Deploy macht der Migrations-Cutover in `homelab-komodo`, danach
  Komodo (UI oder Sync).
- Images mit fester Version, nie `latest`. Bei der Migration dieselbe Version wie im Cluster.
- Hostnamen und andere Werte je Stack stehen im `environment` der TOML (wird zur `.env` im Stack-Ordner) und werden
  in der Compose-Datei als `${VAR}` genutzt. Secrets als Komodo-Variable `[[NAME]]`, nie im Repo.

## Ingress

Zoraxy macht TLS und leitet an Traefik auf `http://<host>:80` weiter (Host-Header erhalten). Apps hängen am externen
Netzwerk `proxy` und setzen Traefik-Labels:

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

Traefik spricht die Docker-API nur über den Socket-Proxy (Netzwerk `socket_proxy`, intern, nur lesend). Andere
Dienste, die die Docker-API brauchen (z. B. Alloy), hängen sich an dasselbe Netzwerk.

## Stacks

| Stack        | Hostnamen                           | Hinweis                                         |
|--------------|-------------------------------------|-------------------------------------------------|
| `traefik`    | –                                   | Port 80, mit Socket-Proxy, `deploy = true`      |
| `excalidraw` | `draw.apps.lan`, `ws-draw.apps.lan` | zustandslos, Collab-Server braucht eigene Route |
