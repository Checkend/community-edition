# Checkend Community Edition

Self-hosted error monitoring for your applications. This repository provides everything you need to run [Checkend](https://github.com/Checkend/checkend) on your own server.

## Prerequisites

- Linux server with at least 1 GB RAM
- Git
- Docker and Docker Compose (the setup script can install these automatically on Ubuntu/Debian)

## Quick Start

### 1. Clone this repository

```bash
sudo git clone https://github.com/Checkend/community-edition.git /opt/checkend
sudo chown -R $USER:$USER /opt/checkend
cd /opt/checkend
```

### 2. Run setup

```bash
./setup.sh
```

The setup script will:
- Install Docker and Docker Compose if needed (Ubuntu/Debian)
- Configure docker group permissions
- Clone the Checkend application source
- Generate secure secrets
- Configure your deployment mode (direct SSL or reverse proxy)

### 3. Start Checkend

```bash
docker compose up -d --build
```

The first build takes a few minutes. Building locally ensures the image is optimized for your server's architecture.

### 4. Create your account

- **Direct SSL mode:** Visit `https://your-domain.com`
- **Reverse proxy mode:** Configure your proxy to forward to port 3000, then visit your domain

---

## Updating

To update to the latest version:

```bash
cd /opt/checkend
./setup.sh              # Select "update" when prompted
docker compose up -d --build
```

To switch to a specific version, remove the `checkend` directory and re-run setup:

```bash
cd /opt/checkend
rm -rf checkend
./setup.sh              # Enter the version tag (e.g., v1.1.0)
docker compose up -d --build
```

---

## Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `SECRET_KEY_BASE` | Yes | 64+ character secret for encryption |
| `POSTGRES_PASSWORD` | Yes | PostgreSQL database password |
| `THRUSTER_TLS_DOMAIN` | No | Domain for automatic SSL certificates |

### Reverse Proxy Setup

When using a reverse proxy, the setup script creates a `compose.override.yml` that exposes port 3000.

**nginx:**

```nginx
server {
    listen 443 ssl;
    server_name checkend.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Caddy:**

```
checkend.example.com {
    reverse_proxy localhost:3000
}
```

---

## Data & Backups

All data is stored in Docker volumes:

- `storage` - Uploaded files and Active Storage data
- `postgres_data` - PostgreSQL database

**Backup database:**

```bash
cd /opt/checkend
docker compose exec db pg_dump -U checkend checkend_production > backup.sql
```

**Backup storage:**

```bash
cd /opt/checkend
docker run --rm -v checkend_storage:/data -v $(pwd):/backup alpine tar czf /backup/storage.tar.gz -C /data .
```

---

## Troubleshooting

**View logs:**

```bash
cd /opt/checkend
docker compose logs -f app
```

**Access Rails console:**

```bash
cd /opt/checkend
docker compose exec app bin/rails console
```

**Reset database:**

```bash
cd /opt/checkend
docker compose down
docker volume rm checkend_postgres_data
docker compose up -d --build
```

---

## License

Checkend is available under the [O'Saasy license](https://osaasy.dev/). You can freely use, modify, and self-host for your own organization.

## Support

- [GitHub Issues](https://github.com/Checkend/checkend/issues) - Bug reports and feature requests
- [GitHub Discussions](https://github.com/Checkend/checkend/discussions) - Questions and community support
