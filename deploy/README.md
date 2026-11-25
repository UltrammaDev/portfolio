# deploy

Резервные копии конфигов, которые живут только на VPS и нигде больше.

| Файл | Откуда | Куда ставить |
|---|---|---|
| `Caddyfile` | VPS `217.60.151.199:/etc/caddy/Caddyfile` | та же машина, тот же путь |

## Caddyfile

Обслуживает self-hosted копию портфолио из `/var/www/portfolio` на
`https://217.60.151.199.sslip.io`. Это отдельный контур: на github.io лежит
исходник, а сюда выкладывается сборка `dist/` (CSS вшит инлайном).

Правки вносить на VPS, затем забирать копию сюда:

```bash
ssh root@217.60.151.199 'cat /etc/caddy/Caddyfile' > deploy/Caddyfile
```

Проверить, что копия совпадает с боевой:

```bash
ssh root@217.60.151.199 'md5sum /etc/caddy/Caddyfile'
md5sum deploy/Caddyfile
```

Применить и проверить конфиг на VPS:

```bash
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```