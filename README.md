# OrderFlow — Event-Driven Order Processing System

Four Spring Boot microservices coordinating an order lifecycle over Apache Kafka,
with a saga-based compensation flow that rolls back inventory when payment fails.

**Stack:** Java 21 · Spring Boot 4.1 · Apache Kafka (KRaft) · PostgreSQL 16 · Redis 7 · Docker

## Architecture

```
              POST /orders
                   │
                   ▼
        ┌──────────────────┐        order.created         ┌────────────────────┐
        │  order-service   │ ───────────────────────────▶ │ inventory-service  │
        │     :8081        │                              │       :8082        │
        └──────────────────┘                              └────────────────────┘
             ▲   ▲   ▲                                       │            │
             │   │   │                            inventory.reserved   inventory.rejected
             │   │   │                                       ▼            │
             │   │   │                              ┌────────────────────┐│
             │   │   └───────── payment.succeeded ──│  payment-service   ││
             │   │                                  │       :8083        │
             │   └───────────── payment.failed ─────└────────────────────┘
             │                                                 │
             │                                    inventory.release (compensation)
             │                                                 ▼
             │                                       back to inventory-service
             │
             └── order.status.changed ──▶ notification-service :8084
```

## Event flow

**Happy path**
1. `order-service` persists the order as `PENDING`, publishes `order.created`.
2. `inventory-service` reserves stock, publishes `inventory.reserved`.
3. `payment-service` charges, publishes `payment.succeeded`.
4. `order-service` moves the order to `CONFIRMED`, publishes `order.status.changed`.
5. `notification-service` consumes and logs/sends the confirmation.

**Saga compensation path (the interesting one)**
1–2. Same as above — stock is reserved.
3. Payment fails after retries → `payment.failed` lands in the DLQ *and* is published.
4. `order-service` marks the order `FAILED` and publishes `inventory.release`.
5. `inventory-service` un-reserves the stock. System is consistent again.

Every consumer is **idempotent**: each event carries an `eventId`, and consumers
record processed ids so a redelivery is a no-op rather than a double charge.

## Kafka topics

| Topic                  | Producer            | Consumer(s)                    | Key       |
|------------------------|---------------------|--------------------------------|-----------|
| `order.created`        | order-service       | inventory-service              | `orderId` |
| `inventory.reserved`   | inventory-service   | payment-service                | `orderId` |
| `inventory.rejected`   | inventory-service   | order-service                  | `orderId` |
| `inventory.release`    | order-service       | inventory-service              | `orderId` |
| `payment.succeeded`    | payment-service     | order-service                  | `orderId` |
| `payment.failed`       | payment-service     | order-service                  | `orderId` |
| `order.status.changed` | order-service       | notification-service           | `orderId` |
| `*.DLT`                | Spring retry infra  | (inspection / replay)          | `orderId` |

Keying by `orderId` guarantees per-order ordering within a partition.

## Running the infrastructure

```bash
docker compose up -d      # Kafka, Postgres, Redis, Kafka UI
docker compose ps         # all should be healthy
docker compose down       # stop (add -v to wipe Postgres data)
```

| Service    | Address                | Credentials           |
|------------|------------------------|-----------------------|
| Kafka      | `localhost:9092`       | —                     |
| Postgres   | `localhost:5432`       | `orderflow`/`orderflow` (db `orderflow`) |
| Redis      | `localhost:6379`       | —                     |
| Kafka UI   | http://localhost:8085  | —                     |

Each service owns a Postgres **schema** (`orders`, `inventory`, `payments`,
`notifications`) — the service-per-database boundary without four containers.

## Running a service

```bash
cd order-service
./mvnw spring-boot:run
```

## Roadmap

**Week 1 — foundation**
- [x] Docker infrastructure: Kafka (KRaft), Postgres, Redis
- [ ] `order-service`: Order entity, repository, `POST /orders`, `GET /orders/{id}`
- [ ] Publish `order.created` on order creation
- [ ] `inventory-service`: consume `order.created`, reserve stock

**Week 2 — the saga**
- [ ] `payment-service`: consume `inventory.reserved`, simulate success/failure
- [ ] Compensation: `payment.failed` → `inventory.release` → stock restored
- [ ] Idempotent consumers keyed on `eventId`
- [ ] Retry + dead-letter topics via `DefaultErrorHandler`

**Week 3 — performance**
- [ ] `notification-service` consuming `order.status.changed`
- [ ] Indexes on the inventory lookup path; measure baseline latency
- [ ] Redis cache-aside over inventory lookups; measure again
- [ ] JMeter load test at 500 req/s, record before/after numbers

**Week 4 — deployment**
- [ ] Dockerfile per service, added to `docker-compose.yml`
- [ ] GitHub Actions: build + test on push
- [ ] Deploy to AWS EC2
