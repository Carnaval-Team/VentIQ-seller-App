# 11 - Operational Runbooks

## 11.1 Overview

This document contains Standard Operating Procedures (SOP) for OpenWA operations, including incident response, maintenance procedures, and troubleshooting guides.

### Runbook Structure

Each runbook follows this format:

```
## Runbook: [Title]
### Trigger
### Impact
### Prerequisites
### Steps
### Verification
### Rollback
```

## 11.2 Incident Response

### Runbook: Service Down

**Trigger:** Health check failing, API not responding

**Impact:** All sessions affected, messages not processing

**Prerequisites:**
- SSH access to server
- Docker CLI access
- Database access

**Steps:**

```bash
# 1. Check container status
docker compose ps

# 2. Check container logs
docker compose logs --tail=100 openwa

# 3. Check system resources
docker stats --no-stream
df -h
free -m

# 4. Identify root cause
# A. Container crashed
docker compose logs openwa 2>&1 | grep -i "error\|fatal\|crash"

# B. Out of memory
docker compose logs openwa 2>&1 | grep -i "oom\|memory"

# C. Database connection
docker compose logs openwa 2>&1 | grep -i "database\|connection refused"

# 5. Apply fix based on cause:

# A. Simple restart
docker compose restart openwa

# B. Full restart with cleanup
docker compose down
docker compose up -d

# C. Memory issues - increase limit
# Edit docker-compose.yml and increase memory limit
docker compose up -d

# D. Database issues
docker compose restart postgres
# Wait for postgres to be ready
sleep 10
docker compose restart openwa
```

**Verification:**

```bash
# Check health
curl http://localhost:2785/health

# Check all sessions reconnected
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions | jq '.[].status'

# Send test message
curl -X POST http://localhost:2785/api/sessions/default/messages \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"phone": "628xxx@c.us", "type": "text", "body": "Test after restart"}'
```

**Rollback:** Restore from backup if data corruption detected (see Runbook: Restore from Backup)

---

### Runbook: Session Disconnected

**Trigger:** Session status changed to DISCONNECTED, webhook not receiving messages

**Impact:** Single session affected

**Prerequisites:**
- API Key
- Physical access to phone (if QR needed)

**Steps:**

```bash
# 1. Check session status
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions/{sessionId}

# 2. Check if auto-reconnect is working
docker compose logs openwa 2>&1 | grep -i "{sessionId}" | tail -20

# 3. Try session restart
curl -X POST -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions/{sessionId}/restart

# 4. Wait for reconnection (30 seconds)
sleep 30

# 5. Check status again
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions/{sessionId}

# 6. If still disconnected, check phone:
#    - Is phone connected to internet?
#    - Is WhatsApp Web still linked in phone settings?
#    - Has the phone been inactive for 14+ days?

# 7. If need to re-scan QR:
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions/{sessionId}/qr

# Display QR in terminal (requires qrencode)
curl -s -H "X-API-Key: $API_KEY" \
  "http://localhost:2785/api/sessions/{sessionId}/qr?format=raw" | qrencode -t ANSI
```

**Verification:**

```bash
# Session connected
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions/{sessionId} | jq '.status'
# Expected: "CONNECTED"

# Test message
curl -X POST http://localhost:2785/api/sessions/{sessionId}/messages \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"phone": "628xxx@c.us", "type": "text", "body": "Session reconnected"}'
```

---

### Runbook: High Memory Usage

**Trigger:** Memory usage > 80%, alerts from monitoring

**Impact:** Performance degradation, potential OOM

**Prerequisites:**
- SSH access
- Docker CLI

**Steps:**

```bash
# 1. Check current memory usage
docker stats --no-stream openwa
free -m

# 2. Identify memory consumers
# Check per-session memory
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/metrics/memory

# 3. Check for memory leaks
docker compose logs openwa 2>&1 | grep -i "heap\|memory\|gc"

# 4. Immediate actions:

# A. Clear message cache
curl -X POST -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/cache/clear

# B. Restart container (will reconnect sessions)
docker compose restart openwa

# C. If caused by too many sessions:
# List sessions sorted by memory
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions?sort=memory

# Consider removing unused sessions

# 5. Long-term fix:
# Edit docker-compose.yml
# Increase memory limit or reduce max sessions
```

**Verification:**

```bash
# Memory below threshold
docker stats --no-stream openwa
# Expected: Memory usage < 80%

# All sessions still connected
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions | jq '.[].status'
```

---

### Runbook: Webhook Delivery Failure

**Trigger:** Webhook success rate < 95%, alert from monitoring

**Impact:** External systems not receiving events

**Prerequisites:**
- API Key
- Access to webhook endpoint

**Steps:**

```bash
# 1. Check webhook status
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions/{sessionId}/webhooks

# 2. Check recent webhook logs
curl -H "X-API-Key: $API_KEY" \
  "http://localhost:2785/api/sessions/{sessionId}/webhooks/{webhookId}/logs?status=failed&limit=20"

# 3. Identify failure reason:
# A. Endpoint not responding
curl -v https://your-webhook-endpoint.com/openwa

# B. SSL certificate issues
curl -v --insecure https://your-webhook-endpoint.com/openwa

# C. Timeout
curl -v --max-time 30 https://your-webhook-endpoint.com/openwa

# D. Authentication failed
curl -v -H "Authorization: Bearer token" \
  https://your-webhook-endpoint.com/openwa

# 4. Test webhook delivery
curl -X POST -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions/{sessionId}/webhooks/{webhookId}/test

# 5. Fix based on cause:

# A. Update webhook URL
curl -X PATCH http://localhost:2785/api/sessions/{sessionId}/webhooks/{webhookId} \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://new-endpoint.com/webhook"}'

# B. Update authentication
curl -X PATCH http://localhost:2785/api/sessions/{sessionId}/webhooks/{webhookId} \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"headers": {"Authorization": "Bearer new-token"}}'

# C. Temporarily disable and re-enable
curl -X POST -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions/{sessionId}/webhooks/{webhookId}/disable

curl -X POST -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions/{sessionId}/webhooks/{webhookId}/enable

# 6. Retry failed deliveries
curl -X POST -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions/{sessionId}/webhooks/{webhookId}/retry-failed
```

**Verification:**

```bash
# Webhook test successful
curl -X POST -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions/{sessionId}/webhooks/{webhookId}/test
# Expected: {"status": "success"}

# Recent deliveries successful
curl -H "X-API-Key: $API_KEY" \
  "http://localhost:2785/api/sessions/{sessionId}/webhooks/{webhookId}/logs?limit=5" | jq '.[].status'
# Expected: all "success"
```

---

## 11.3 Maintenance Procedures

### Runbook: Scheduled Maintenance

**Trigger:** Planned maintenance window

**Impact:** Service downtime during maintenance

**Prerequisites:**
- Scheduled maintenance window
- Backup verified
- User notification sent

**Steps:**

```bash
# 1. Pre-maintenance checks (1 hour before)
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/health/detailed
docker stats --no-stream

# 2. Notify users (via webhook or external system)
# Send maintenance notification

# 3. Create backup
./scripts/backup.sh

# Verify backup
ls -la /backups/openwa/$(date +%Y%m%d)/

# 4. Stop accepting new requests (if using load balancer)
# Remove from load balancer or set to maintenance mode

# 5. Wait for in-flight requests to complete (30 seconds)
sleep 30

# 6. Stop services
docker compose down

# 7. Perform maintenance tasks:
# - System updates
# - Docker updates
# - Configuration changes
# - Database migrations

# 8. Start services
docker compose up -d

# 9. Wait for health
sleep 30
curl http://localhost:2785/health

# 10. Verify all sessions reconnected
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions | jq '.[].status'

# 11. Re-enable in load balancer

# 12. Send maintenance complete notification
```

**Verification:**

```bash
# All services healthy
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/health/detailed

# All sessions connected
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions | jq '[.[] | select(.status == "CONNECTED")] | length'

# Test message flow
# Send test message and verify webhook received
```

---

### Runbook: Version Upgrade

**Trigger:** New version release

**Impact:** Brief downtime during upgrade

**Prerequisites:**
- Backup completed
- Release notes reviewed
- Breaking changes identified
- Rollback plan ready

**Steps:**

```bash
# 1. Review release notes
# Check for breaking changes, migration requirements

# 2. Create backup
./scripts/backup.sh
BACKUP_DIR="/backups/openwa/$(date +%Y%m%d-%H%M%S)"

# 3. Export current state
docker compose exec openwa npm run export -- --output /tmp/export.json
docker cp openwa:/tmp/export.json $BACKUP_DIR/

# 4. Stop services
docker compose down

# 5. Update version in docker-compose.yml
# Change: image: ghcr.io/rmyndharis/openwa:0.1.0
# To:     image: ghcr.io/rmyndharis/openwa:0.2.0

# 6. Pull new image
docker compose pull

# 7. Run database migrations (if any)
docker compose run --rm openwa npm run migration:run

# 8. Start services
docker compose up -d

# 9. Wait for health
sleep 30
curl http://localhost:2785/health

# 10. Verify version
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/health/detailed | jq '.version'

# 11. Verify all sessions
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions

# 12. Test critical flows
./scripts/smoke-test.sh
```

**Verification:**

```bash
# Correct version
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/health/detailed | jq '.version'
# Expected: "0.2.0"

# All tests pass
./scripts/smoke-test.sh
# Expected: All tests pass
```

**Rollback:**

```bash
# 1. Stop services
docker compose down

# 2. Revert docker-compose.yml to previous version

# 3. Restore database
cp $BACKUP_DIR/openwa.db ./data/

# 4. Start with old version
docker compose up -d

# 5. Verify rollback
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/health/detailed | jq '.version'
```

---

### Runbook: Database Backup

**Trigger:** Daily schedule, before maintenance, before upgrade

**Impact:** None (online backup)

**Prerequisites:**
- Sufficient disk space
- Backup storage accessible

**Steps:**

```bash
#!/bin/bash
# scripts/backup.sh

set -e

DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/backups/openwa/$DATE"
RETENTION_DAYS=30

echo "Starting backup to $BACKUP_DIR"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# 1. Backup database
if [ "$DATABASE_ADAPTER" = "postgresql" ]; then
    echo "Backing up PostgreSQL..."
    docker compose exec -T postgres pg_dump -U postgres openwa > "$BACKUP_DIR/database.sql"
else
    echo "Backing up SQLite..."
    # Use SQLite online backup
    docker compose exec openwa sqlite3 /app/data/openwa.db ".backup /tmp/backup.db"
    docker cp openwa:/tmp/backup.db "$BACKUP_DIR/openwa.db"
fi

# 2. Backup auth sessions
echo "Backing up auth sessions..."
cp -r ./data/.wwebjs_auth "$BACKUP_DIR/"

# 3. Backup configuration
echo "Backing up configuration..."
cp .env "$BACKUP_DIR/"
cp docker-compose.yml "$BACKUP_DIR/"

# 4. Backup media (optional, can be large)
if [ "$BACKUP_MEDIA" = "true" ]; then
    echo "Backing up media..."
    cp -r ./data/media "$BACKUP_DIR/"
fi

# 5. Create archive
echo "Creating archive..."
tar -czf "$BACKUP_DIR.tar.gz" -C "/backups/openwa" "$DATE"
rm -rf "$BACKUP_DIR"

# 6. Cleanup old backups
echo "Cleaning up old backups..."
find /backups/openwa -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete

# 7. Verify backup
echo "Verifying backup..."
tar -tzf "$BACKUP_DIR.tar.gz" > /dev/null

echo "Backup completed: $BACKUP_DIR.tar.gz"
echo "Size: $(du -h "$BACKUP_DIR.tar.gz" | cut -f1)"
```

**Verification:**

```bash
# List backup contents
tar -tzf $BACKUP_DIR.tar.gz

# Check backup size
du -h $BACKUP_DIR.tar.gz

# Test restore to temp location
mkdir /tmp/restore-test
tar -xzf $BACKUP_DIR.tar.gz -C /tmp/restore-test
ls -la /tmp/restore-test/
rm -rf /tmp/restore-test
```

---

### Runbook: Restore from Backup

**Trigger:** Data corruption, accidental deletion, disaster recovery

**Impact:** Service downtime during restore

**Prerequisites:**
- Valid backup file
- Sufficient disk space
- SSH access

**Steps:**

```bash
#!/bin/bash
# scripts/restore.sh

BACKUP_FILE=$1

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: ./restore.sh <backup-file.tar.gz>"
    exit 1
fi

echo "WARNING: This will overwrite current data!"
read -p "Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    exit 0
fi

set -e

# 1. Stop services
echo "Stopping services..."
docker compose down

# 2. Extract backup
echo "Extracting backup..."
RESTORE_DIR="/tmp/restore-$(date +%s)"
mkdir -p "$RESTORE_DIR"
tar -xzf "$BACKUP_FILE" -C "$RESTORE_DIR"

# 3. Restore database
if [ -f "$RESTORE_DIR/*/database.sql" ]; then
    echo "Restoring PostgreSQL..."
    docker compose up -d postgres
    sleep 10
    docker compose exec -T postgres psql -U postgres openwa < "$RESTORE_DIR"/*/database.sql
elif [ -f "$RESTORE_DIR/*/openwa.db" ]; then
    echo "Restoring SQLite..."
    cp "$RESTORE_DIR"/*/openwa.db ./data/
fi

# 4. Restore auth sessions
echo "Restoring auth sessions..."
rm -rf ./data/.wwebjs_auth
cp -r "$RESTORE_DIR"/*/.wwebjs_auth ./data/

# 5. Restore configuration (optional - review first)
echo "Configuration files in backup:"
ls -la "$RESTORE_DIR"/*/.env "$RESTORE_DIR"/*/docker-compose.yml
read -p "Restore configuration? (yes/no): " RESTORE_CONFIG
if [ "$RESTORE_CONFIG" = "yes" ]; then
    cp "$RESTORE_DIR"/*/.env .
    cp "$RESTORE_DIR"/*/docker-compose.yml .
fi

# 6. Start services
echo "Starting services..."
docker compose up -d

# 7. Wait for health
echo "Waiting for health check..."
sleep 30
curl http://localhost:2785/health

# 8. Cleanup
rm -rf "$RESTORE_DIR"

echo "Restore completed!"
```

**Verification:**

```bash
# Health check
curl http://localhost:2785/health

# Verify sessions
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions

# Verify data integrity
curl -H "X-API-Key: $API_KEY" \
  http://localhost:2785/api/sessions/default/messages?limit=1
```

---

## 11.4 Monitoring & Alerting

### Alert Response Matrix

| Alert | Severity | Response Time | Runbook |
|-------|----------|---------------|---------|
| Service Down | Critical | 5 min | Service Down |
| High Memory | Warning | 30 min | High Memory Usage |
| Session Disconnected | Warning | 15 min | Session Disconnected |
| Webhook Failures > 5% | Warning | 30 min | Webhook Delivery Failure |
| Disk Space < 10% | Critical | 15 min | Disk Space Low |
| Certificate Expiry < 7 days | Warning | 24 hours | Certificate Renewal |

### Runbook: Certificate Renewal

**Trigger:** Certificate expiring in < 7 days

**Impact:** HTTPS will fail when expired

**Steps:**

```bash
# Using certbot
sudo certbot renew

# Verify renewal
sudo certbot certificates

# Restart nginx/proxy
sudo systemctl restart nginx
# or
docker compose restart nginx

# Verify HTTPS
curl -v https://api.your-domain.com/health
```

---

### Runbook: Disk Space Low

**Trigger:** Disk usage > 90%

**Impact:** Service may fail to write data

**Steps:**

```bash
# 1. Check disk usage
df -h

# 2. Find large files
du -sh /var/lib/docker/*
du -sh ./data/*
du -sh ./logs/*

# 3. Clean up:

# A. Docker cleanup
docker system prune -af
docker volume prune -f

# B. Old logs
find ./logs -name "*.log" -mtime +7 -delete

# C. Old backups
find /backups -name "*.tar.gz" -mtime +30 -delete

# D. Message attachments (if backed up)
# Warning: This deletes media files
find ./data/media -mtime +30 -delete

# E. Truncate large log files
truncate -s 0 ./logs/openwa.log

# 4. Verify
df -h
```

---

## 11.5 Capacity Planning

### Resource Estimation

```
Per Session Requirements:
- Memory: 300-500MB (average 400MB)
- CPU: 0.1-0.2 cores idle, 0.5 cores peak
- Disk: 100MB base + ~1KB per message

Server Sizing:
┌──────────────┬─────────┬──────┬───────────┐
│ Sessions     │ RAM     │ CPU  │ Disk      │
├──────────────┼─────────┼──────┼───────────┤
│ 1-3          │ 2 GB    │ 2    │ 20 GB     │
│ 4-10         │ 4 GB    │ 4    │ 50 GB     │
│ 11-20        │ 8 GB    │ 8    │ 100 GB    │
│ 21-50        │ 16 GB   │ 16   │ 200 GB    │
│ 50+          │ 32 GB+  │ 32+  │ 500 GB+   │
└──────────────┴─────────┴──────┴───────────┘
```

### Scaling Decision Tree

```mermaid
flowchart TD
    A[Performance Issues?] --> B{CPU > 80%?}
    B -->|Yes| C[Add more CPU/Horizontal scale]
    B -->|No| D{Memory > 80%?}
    D -->|Yes| E[Add more RAM/Reduce sessions]
    D -->|No| F{Disk > 80%?}
    F -->|Yes| G[Add storage/Cleanup]
    F -->|No| H{Response time > 1s?}
    H -->|Yes| I[Check database/Add indexes]
    H -->|No| J[System OK]
```

---

## 11.6 Emergency Contacts

```
On-Call Schedule:
- Primary: Check PagerDuty/OpsGenie
- Secondary: Check escalation policy

Escalation Path:
1. On-call engineer (5 min response)
2. Team lead (15 min response)
3. Engineering manager (30 min response)

External Contacts:
- Cloud provider support: [support portal URL]
- Domain registrar: [support email]
- SSL provider: [support portal]
```
---

<div align="center">

[← 10 - DevOps & Infrastructure](./10-devops-infrastructure.md) · [Documentation Index](./README.md) · [Next: 12 - Troubleshooting & FAQ →](./12-troubleshooting-faq.md)

</div>
