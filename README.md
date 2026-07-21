# OrderFlow

An online store's order system, split into 4 small services that talk to each
other through Kafka messages instead of calling each other directly.

**Built with:** Java 21, Spring Boot, Kafka, PostgreSQL, Redis, Docker

## What it does

You send an order. Four services handle it, one job each:

| Service | Port | Job |
|---|---|---|
| order-service | 8081 | Takes the order, tracks its status |
| inventory-service | 8082 | Sets aside the items |
| payment-service | 8083 | Charges the customer |
| notification-service | 8084 | Tells the customer what happened |

They never call each other directly. Each one sends a message to Kafka, and
whoever cares picks it up. So if payment-service is down for a minute, orders
still get taken — the messages just wait.

## How an order flows

**When everything works:**

```
You  ──POST /orders──▶  order-service   (saves it as PENDING)
                             │
                             │ "order.created"
                             ▼
                       inventory-service  (sets items aside)
                             │
                             │ "inventory.reserved"
                             ▼
                        payment-service   (charges the card)
                             │
                             │ "payment.succeeded"
                             ▼
                        order-service     (marks it CONFIRMED)
                             │
                             │ "order.status.changed"
                             ▼
                     notification-service  (emails the customer)
```

**When the payment fails:**

The items are already set aside at that point. We can't just stop — that stock
would be stuck forever. So we undo it:

```
payment-service  ──"payment.failed"──▶  order-service  (marks it FAILED)
                                             │
                                             │ "inventory.release"
                                             ▼
                                      inventory-service  (puts the items back)
```

Undoing earlier steps when a later one fails is called a **saga**. It's how you
keep things straight when there's no single database transaction to roll back.

**One more thing:** Kafka can deliver the same message twice. So every message
carries an `eventId`, and each service remembers which ids it already handled.
See a repeat, skip it. Otherwise a customer could get charged twice.

## The messages

| Message | Sent by | Read by |
|---|---|---|
| `order.created` | order-service | inventory-service |
| `inventory.reserved` | inventory-service | payment-service |
| `inventory.rejected` | inventory-service | order-service |
| `inventory.release` | order-service | inventory-service |
| `payment.succeeded` | payment-service | order-service |
| `payment.failed` | payment-service | order-service |
| `order.status.changed` | order-service | notification-service |

Every message is tagged with its `orderId`. That's what keeps one order's
messages in the right order.

If a message keeps failing, Kafka moves it to a `.DLT` topic (a "dead letter"
pile) so it stops blocking everything behind it and you can look at it later.

## Running it

Start the databases and Kafka:

```bash
docker compose up -d      # start
docker compose ps         # check they're all healthy
docker compose down       # stop
```

| What | Where | Login |
|---|---|---|
| Kafka | localhost:9092 | — |
| Postgres | localhost:5432 | orderflow / orderflow |
| Redis | localhost:6379 | — |
| Kafka UI (see messages in a browser) | http://localhost:8085 | — |

Start a service:

```bash
cd order-service
./mvnw spring-boot:run
```

Note: use `./mvnw`, not `mvn`. It's included in the project, so you don't have
to install Maven.

Each service gets its own section of the Postgres database (`orders`,
`inventory`, `payments`, `notifications`) so they don't touch each other's
tables.

## To do

**Week 1 — get it running**
- [x] Docker: Kafka, Postgres, Redis
- [ ] order-service: save an order, read it back
- [ ] Send `order.created` when an order comes in
- [ ] inventory-service: read `order.created`, set items aside

**Week 2 — the saga**
- [ ] payment-service: charge, sometimes fail on purpose
- [ ] Put the items back when payment fails
- [ ] Skip messages we've already handled
- [ ] Retry failed messages, then send them to `.DLT`

**Week 3 — make it fast**
- [ ] notification-service
- [ ] Time how slow inventory lookups are
- [ ] Add Redis caching, time it again
- [ ] Load test with JMeter, write down the before/after numbers

**Week 4 — deploy it**
- [ ] A Dockerfile for each service
- [ ] GitHub Actions to build and test on every push
- [ ] Run it on AWS EC2
