# 09 - Testing Strategy

## Implementation Status

> **Current Status: Minimal Implementation**
>
> This document outlines the planned testing strategy for OpenWA. The current implementation includes only foundational tests:
>
> | Test Type | Planned | Actual |
> |-----------|---------|--------|
> | Unit Tests | 60% coverage | 3 files |
> | Integration Tests | 30% coverage | Not yet |
> | E2E Tests | Critical paths | Not yet |
>
> **Existing test files:**
> - `src/common/services/logger.service.spec.ts` - Logger functionality
> - `src/modules/health/health.controller.spec.ts` - Health endpoints
> - `src/modules/webhook/utils/idempotency.util.spec.ts` - Idempotency utilities
>
> Comprehensive testing is planned for future releases. The strategy below serves as a guide for contributors and future development phases.

---

## 09.1 Overview

```mermaid
flowchart TB
    subgraph TestPyramid["Testing Pyramid"]
        direction TB
        E2E[E2E Tests<br/>10%]
        INT[Integration Tests<br/>30%]
        UNIT[Unit Tests<br/>60%]
    end
    
    subgraph Types["Test Types"]
        UT[Unit Tests]
        IT[Integration Tests]
        ET[E2E Tests]
        PT[Performance Tests]
        ST[Security Tests]
    end
```

### Testing Goals

| Goal | Target | Current | Priority |
|------|--------|---------|----------|
| Code Coverage | > 80% | ~5% | High |
| Integration Test Coverage | > 70% | 0% | High |
| E2E Critical Paths | 100% | 0% | High |
| Performance Benchmarks | Pass all | Not started | Medium |
| Security Scan | 0 Critical | ✅ Passing | High |

## 09.2 Unit Testing

### Framework & Tools

```json
{
  "devDependencies": {
    "jest": "^29.0.0",
    "@nestjs/testing": "^10.0.0",
    "ts-jest": "^29.0.0"
  }
}
```

### Test Structure

```
src/
├── modules/
│   ├── session/
│   │   ├── session.service.ts
│   │   └── session.service.spec.ts
│   ├── message/
│   │   ├── message.service.ts
│   │   └── message.service.spec.ts
│   └── webhook/
│       ├── webhook.service.ts
│       └── webhook.service.spec.ts
└── common/
    └── utils/
        ├── validator.ts
        └── validator.spec.ts
```

### Unit Test Examples

```typescript
// session.service.spec.ts
describe('SessionService', () => {
  let service: SessionService;
  let engineFactory: jest.Mocked<EngineFactory>;
  let repository: jest.Mocked<SessionRepository>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        SessionService,
        {
          provide: EngineFactory,
          useValue: createMock<EngineFactory>(),
        },
        {
          provide: SessionRepository,
          useValue: createMock<SessionRepository>(),
        },
      ],
    }).compile();

    service = module.get(SessionService);
    engineFactory = module.get(EngineFactory);
    repository = module.get(SessionRepository);
  });

  describe('createSession', () => {
    it('should create a new session with default config', async () => {
      const dto = { name: 'test-session' };
      repository.findByName.mockResolvedValue(null);
      repository.save.mockResolvedValue({ id: 'sess_123', ...dto });

      const result = await service.createSession(dto);

      expect(result.id).toBe('sess_123');
      expect(repository.save).toHaveBeenCalledWith(
        expect.objectContaining({ name: 'test-session' })
      );
    });

    it('should throw error if session name already exists', async () => {
      const dto = { name: 'existing-session' };
      repository.findByName.mockResolvedValue({ id: 'sess_old' });

      await expect(service.createSession(dto))
        .rejects.toThrow('SESSION_ALREADY_EXISTS');
    });
  });

  describe('sendMessage', () => {
    it('should validate chatId format', async () => {
      const invalidChatId = 'invalid-format';

      await expect(
        service.sendMessage('sess_123', invalidChatId, 'Hello')
      ).rejects.toThrow('MESSAGE_INVALID_CHAT_ID');
    });
  });
});
```

### Mocking Guidelines

```typescript
// Mock WhatsApp Engine
const mockEngine = {
  initialize: jest.fn().mockResolvedValue(undefined),
  sendMessage: jest.fn().mockResolvedValue({ messageId: 'msg_123' }),
  getContacts: jest.fn().mockResolvedValue([]),
  disconnect: jest.fn(),
  on: jest.fn(),
};

// Mock Repository
const mockRepository = {
  findById: jest.fn(),
  findByName: jest.fn(),
  save: jest.fn(),
  update: jest.fn(),
  delete: jest.fn(),
};

// Mock HTTP Service (for webhooks)
const mockHttpService = {
  post: jest.fn().mockReturnValue(of({ data: {}, status: 200 })),
};
```

## 09.3 Integration Testing

### Test Database

```yaml
# docker-compose.test.yml
version: '3.8'
services:
  postgres-test:
    image: postgres:15
    environment:
      POSTGRES_DB: openwa_test
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
    ports:
      - "5433:5432"
    tmpfs:
      - /var/lib/postgresql/data
  
  redis-test:
    image: redis:7-alpine
    ports:
      - "6380:6379"
```

### Integration Test Examples

```typescript
// session.integration.spec.ts
describe('Session Integration', () => {
  let app: INestApplication;
  let dataSource: DataSource;

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(EngineFactory)
      .useValue(mockEngineFactory)
      .compile();

    app = module.createNestApplication();
    await app.init();
    dataSource = module.get(DataSource);
  });

  afterAll(async () => {
    await dataSource.destroy();
    await app.close();
  });

  beforeEach(async () => {
    // Clean database before each test
    await dataSource.query('TRUNCATE TABLE sessions CASCADE');
  });

  describe('POST /api/sessions', () => {
    it('should create session and return QR code', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/sessions')
        .set('X-API-Key', 'test-api-key')
        .send({ name: 'integration-test' })
        .expect(201);

      expect(response.body.success).toBe(true);
      expect(response.body.data.status).toBe('SCAN_QR');
      expect(response.body.data.qr).toBeDefined();
    });

    it('should reject duplicate session name', async () => {
      // Create first session
      await request(app.getHttpServer())
        .post('/api/sessions')
        .set('X-API-Key', 'test-api-key')
        .send({ name: 'duplicate-test' })
        .expect(201);

      // Try to create duplicate
      const response = await request(app.getHttpServer())
        .post('/api/sessions')
        .set('X-API-Key', 'test-api-key')
        .send({ name: 'duplicate-test' })
        .expect(409);

      expect(response.body.error.code).toBe('SESSION_ALREADY_EXISTS');
    });
  });

  describe('Webhook Delivery', () => {
    it('should deliver webhook on message received', async () => {
      // Setup webhook endpoint mock
      const webhookServer = await createMockWebhookServer(3001);
      
      // Create session with webhook
      await request(app.getHttpServer())
        .post('/api/sessions')
        .set('X-API-Key', 'test-api-key')
        .send({
          name: 'webhook-test',
          webhook: {
            url: 'http://localhost:3001/webhook',
            events: ['message.received']
          }
        });

      // Simulate incoming message
      await simulateIncomingMessage(app, 'webhook-test', {
        chatId: '628123456789@c.us',
        text: 'Test message'
      });

      // Verify webhook was called
      expect(webhookServer.receivedPayloads).toHaveLength(1);
      expect(webhookServer.receivedPayloads[0].event).toBe('message.received');

      await webhookServer.close();
    });
  });
});
```

## 09.4 E2E Testing

### Critical User Journeys

```mermaid
flowchart LR
    subgraph Journey1["Session Lifecycle"]
        J1A[Create Session] --> J1B[Scan QR]
        J1B --> J1C[Verify Connected]
        J1C --> J1D[Logout]
    end
    
    subgraph Journey2["Messaging Flow"]
        J2A[Get Session] --> J2B[Send Text]
        J2B --> J2C[Verify Sent]
        J2C --> J2D[Check Webhook]
    end
    
    subgraph Journey3["Bulk Operations"]
        J3A[Create Batch] --> J3B[Monitor Progress]
        J3B --> J3C[Verify Results]
    end
```

### E2E Test Scenarios

| ID | Scenario | Steps | Expected Result |
|----|----------|-------|-----------------|
| E2E-001 | Session Creation | Create → Get QR → Verify status | Status = SCAN_QR |
| E2E-002 | Send Text Message | Send text → Check response → Verify webhook | Message delivered + webhook called |
| E2E-003 | Send Media | Send image → Check upload → Verify delivery | Media delivered |
| E2E-004 | Bulk Messaging | Create batch → Monitor → Verify all sent | 100% delivery |
| E2E-005 | Webhook Retry | Setup failing webhook → Verify 3 retries | 3 attempts logged |
| E2E-006 | Rate Limiting | Exceed rate limit → Check 429 response | Proper error + headers |
| E2E-007 | API Key Auth | Invalid key → Valid key → Permission check | Proper auth flow |
| E2E-008 | WebSocket Events | Connect → Subscribe → Receive event | Event delivered |

### E2E Test Implementation

```typescript
// e2e/session.e2e-spec.ts
describe('Session E2E', () => {
  let api: AxiosInstance;

  beforeAll(() => {
    api = axios.create({
      baseURL: process.env.TEST_API_URL || 'http://localhost:2785/api',
      headers: { 'X-API-Key': process.env.TEST_API_KEY }
    });
  });

  describe('Complete Session Lifecycle', () => {
    let sessionId: string;

    it('Step 1: Create new session', async () => {
      const response = await api.post('/sessions', {
        name: `e2e-test-${Date.now()}`
      });

      expect(response.status).toBe(201);
      expect(response.data.data.status).toBe('SCAN_QR');
      sessionId = response.data.data.id;
    });

    it('Step 2: Get QR code', async () => {
      const response = await api.get(`/sessions/${sessionId}/qr`);

      expect(response.status).toBe(200);
      expect(response.data.data.image).toMatch(/^data:image\/png;base64,/);
    });

    it('Step 3: Check session status', async () => {
      const response = await api.get(`/sessions/${sessionId}`);

      expect(response.status).toBe(200);
      expect(response.data.data.id).toBe(sessionId);
    });

    it('Step 4: Delete session', async () => {
      const response = await api.delete(`/sessions/${sessionId}`);

      expect(response.status).toBe(200);
    });

    it('Step 5: Verify session deleted', async () => {
      try {
        await api.get(`/sessions/${sessionId}`);
        fail('Should have thrown 404');
      } catch (error) {
        expect(error.response.status).toBe(404);
      }
    });
  });
});
```

## 09.5 Performance Testing

### Tools

- **k6** - Load testing
- **Artillery** - API stress testing

### Performance Test Scenarios

```javascript
// k6/load-test.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 20 },   // Ramp up
    { duration: '1m', target: 50 },    // Stay at 50 users
    { duration: '30s', target: 100 },  // Peak load
    { duration: '30s', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% requests under 500ms
    http_req_failed: ['rate<0.01'],   // Less than 1% errors
  },
};

const BASE_URL = __ENV.API_URL || 'http://localhost:2785/api';
const API_KEY = __ENV.API_KEY || 'test-key';

export default function () {
  // Test: Get sessions
  const sessionsRes = http.get(`${BASE_URL}/sessions`, {
    headers: { 'X-API-Key': API_KEY },
  });
  
  check(sessionsRes, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  sleep(1);

  // Test: Send message (if session exists)
  if (sessionsRes.json().data?.length > 0) {
    const sessionId = sessionsRes.json().data[0].id;
    const msgRes = http.post(
      `${BASE_URL}/sessions/${sessionId}/messages/send-text`,
      JSON.stringify({
        chatId: '628123456789@c.us',
        text: `Load test message ${Date.now()}`
      }),
      {
        headers: {
          'X-API-Key': API_KEY,
          'Content-Type': 'application/json'
        }
      }
    );

    check(msgRes, {
      'message sent': (r) => r.status === 200 || r.status === 400,
      'response time < 2s': (r) => r.timings.duration < 2000,
    });
  }

  sleep(1);
}
```

### Performance Targets

| Metric | Target | Critical |
|--------|--------|----------|
| API Response Time (p95) | < 500ms | < 1000ms |
| Message Send Latency | < 2s | < 5s |
| QR Generation Time | < 3s | < 5s |
| Throughput | 100 req/s | 50 req/s |
| Memory per Session | < 500MB | < 800MB |
| Concurrent Sessions | 10+ | 5 |

## 09.6 Security Testing

### Checklist

```markdown
## Security Test Checklist

### Authentication
- [ ] API key required for all endpoints
- [ ] Invalid API key returns 401
- [ ] Expired API key rejected
- [ ] API key hash stored (not plain)

### Authorization
- [ ] Permission checks enforced
- [ ] Session isolation (can't access other sessions)
- [ ] IP whitelist working

### Input Validation
- [ ] SQL injection prevented
- [ ] XSS in webhook payloads prevented
- [ ] chatId format validated
- [ ] File upload size limits enforced

### Rate Limiting
- [ ] Rate limits working per endpoint
- [ ] Rate limit headers present
- [ ] 429 response on exceed

### Data Protection
- [ ] Sensitive data encrypted
- [ ] No secrets in logs
- [ ] Session auth state encrypted
```

### Security Test Examples

```typescript
// security.spec.ts
describe('Security Tests', () => {
  describe('Authentication', () => {
    it('should reject request without API key', async () => {
      const response = await request(app.getHttpServer())
        .get('/api/sessions')
        .expect(401);

      expect(response.body.error.code).toBe('UNAUTHORIZED');
    });

    it('should reject invalid API key', async () => {
      const response = await request(app.getHttpServer())
        .get('/api/sessions')
        .set('X-API-Key', 'invalid-key')
        .expect(401);

      expect(response.body.error.code).toBe('UNAUTHORIZED');
    });
  });

  describe('Input Validation', () => {
    it('should reject SQL injection in session name', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/sessions')
        .set('X-API-Key', validApiKey)
        .send({ name: "'; DROP TABLE sessions; --" })
        .expect(400);

      expect(response.body.error.code).toBe('VALIDATION_ERROR');
    });

    it('should reject XSS in webhook URL', async () => {
      const response = await request(app.getHttpServer())
        .post('/api/sessions/sess_123/webhooks')
        .set('X-API-Key', validApiKey)
        .send({
          url: 'javascript:alert(1)',
          events: ['message.received']
        })
        .expect(400);

      expect(response.body.error.code).toBe('WEBHOOK_URL_INVALID');
    });
  });

  describe('Rate Limiting', () => {
    it('should block after exceeding rate limit', async () => {
      // Send 35 requests (limit is 30)
      for (let i = 0; i < 35; i++) {
        await request(app.getHttpServer())
          .get('/api/sessions')
          .set('X-API-Key', validApiKey);
      }

      const response = await request(app.getHttpServer())
        .get('/api/sessions')
        .set('X-API-Key', validApiKey)
        .expect(429);

      expect(response.headers['retry-after']).toBeDefined();
    });
  });
});
```

## 09.7 CI/CD Integration

### GitHub Actions Workflow

```yaml
# .github/workflows/test.yml
name: Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      
      - run: npm ci
      - run: npm run test:cov
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage/lcov.info

  integration-tests:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_DB: openwa_test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
        ports:
          - 5432:5432
      redis:
        image: redis:7
        ports:
          - 6379:6379
    
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      
      - run: npm ci
      - run: npm run test:integration
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/openwa_test
          REDIS_URL: redis://localhost:6379

  e2e-tests:
    runs-on: ubuntu-latest
    needs: [unit-tests, integration-tests]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      
      - run: npm ci
      - run: npm run build
      - run: npm run test:e2e

  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm audit --audit-level=high
      - uses: snyk/actions/node@master
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
```

## 09.8 Test Reporting

### Coverage Requirements

| Area | Minimum Coverage |
|------|------------------|
| Services | 85% |
| Controllers | 80% |
| Guards | 90% |
| Utils | 95% |
| Overall | 80% |

### Test Report Template

```markdown
## Test Execution Report

**Date:** YYYY-MM-DD
**Version:** X.X.X
**Environment:** CI / Staging / Production

### Summary

| Type | Total | Passed | Failed | Skipped |
|------|-------|--------|--------|---------|
| Unit | 150 | 148 | 2 | 0 |
| Integration | 45 | 45 | 0 | 0 |
| E2E | 15 | 14 | 1 | 0 |

### Coverage

| Module | Lines | Functions | Branches |
|--------|-------|-----------|----------|
| session | 92% | 95% | 88% |
| message | 85% | 90% | 82% |
| webhook | 88% | 92% | 85% |
| **Total** | **87%** | **91%** | **84%** |

### Failed Tests

1. `message.service.spec.ts` - sendMedia timeout
   - **Cause:** Mock timeout misconfigured
   - **Action:** Fix in PR #123

### Performance Results

| Test | Target | Actual | Status |
|------|--------|--------|--------|
| API p95 latency | <500ms | 320ms | ✅ |
| Throughput | 100 req/s | 125 req/s | ✅ |
```
---

<div align="center">

[← 08 - Development Guidelines](./08-development-guidelines.md) · [Documentation Index](./README.md) · [Next: 10 - DevOps & Infrastructure →](./10-devops-infrastructure.md)

</div>
