# Database selection reference (PACELC)

Load this **only** when a feature introduces a new datastore, or an existing datastore must
start handling a materially different use case (new access pattern, consistency requirement,
scale target, or global distribution need). Do not load for features that just reuse an
already-chosen datastore unchanged — this is reference material, not part of every
Architecture Document.

**How to use**: match the feature's actual requirement — consistency vs. availability
trade-off under partition (PACELC), data shape, and query pattern — against the table below.
Prefer the narrowest fit; do not default to a distributed store when a single-node relational
DB satisfies the consistency/scale requirement. Verify current version/licensing/pricing via
context7 or web search before committing to a choice — this table is a starting shortlist,
not a substitute for checking the vendor's current docs.

| Database | PACELC | Type | Use cases | Internal mechanism | Refactorable later? | Note |
|---|---|---|---|---|---|---|
| Cassandra | AP / EL | Columnar | Social networks, time series, catalogs (Netflix), IoT, healthcare, platforms requiring massive write throughput, globally distributed product catalogs, 24/7 high-availability apps | Quorum | ✅ | RF/2+1 — e.g. 10/2=5+1=6 |
| MongoDB | CP / EC | Document (ACID) | General web/mobile apps, e-commerce product catalogs, log data, rapid prototyping | Raft | ✅ | WriteConcern / ReadConcern tunable |
| DynamoDB (AWS) | AP / EL | Key-value | High-traffic web/mobile apps, game leaderboards, user profiles, clickstreams, history, e-commerce carts, telemetry | Quorum | ✅ | Can enable strong read/write via config |
| CockroachDB | CP / EC | Distributed relational (ACID) | Financial/banking apps needing strong ACID, global inventory management, multi-region game backends, payment processing, e-commerce (stock/orders/pricing) | Raft | ✅ | Eventual-consistency mode recently enabled |
| SpannerDB (Google) | CP / EC | Distributed relational (ACID) | Global fintech/payments, multi-region high-scale gaming (incl. inventory/player state), mission-critical backends needing 99.999% SLA, systems needing distributed transactions with absolute consistency | Paxos | ✅ | Atomic clocks, TrueTime, Google private network, hardware control, 99.999% availability |
| PostgreSQL | CP / EC | Single-node relational (ACID) | Web apps, enterprise systems, e-commerce, ERP, CMS, dynamic sites, systems needing strong consistency/relationships/data structure | WAL-based replication | ❌ | Single-node; depends on external tooling for distribution |
| Redis | AP / EL | Key-value | Cache, messaging, session control | Sentinel | ❌ | Quorum ack configurable, but AP behavior doesn't change |
| Etcd | CP / EC | Key-value | Cluster management/orchestration (Kubernetes), app/system config management, service discovery | Raft | ❌ | Fully consistency-focused; no eventual mode |
| Riak | AP / EL | Key-value | High-traffic ad delivery, sensor data/log storage, IoT, logs, large volumes | Quorum | ⚠️ | "Strong Consistency" exists as experimental, not recommended in production |
| Neo4j | CP / EC | Graph | Fraud detection, personalized recommendations, suspicious-activity/AML detection, social networks, real-time anomaly detection | Raft | ✅ | Runs in HA cluster mode (eventual) or strongly consistent mode |
| Elasticsearch | CP / EC | Document | Real-time search/log analytics (ELK stack), full-text search (e-commerce, content platforms, corporate apps, internal knowledge bases) | Own mechanism (quorum-based) | ✅ | Consistency/availability tunable via `wait_for_active_shards` |
| FoundationDB | CP / EC | Distributed transactional key-value | Metadata storage for large-scale systems, custom DB/data-model construction, iCloud (Apple CloudKit) | Paxos | ❌ | End-to-end CP; always sacrifices availability |
| ScyllaDB | AP / EL | Columnar | High-ingestion time-series systems, online gaming/betting backends, real-time adtech/personalization, Cassandra migrations seeking extreme low latency + higher throughput (Discord) | Raft | ✅ | Tunable consistency; metadata now uses Raft (strong) |
| Couchbase | CP / EC | Document | User profile/content management for web/mobile, high-traffic product catalogs/e-commerce, game session/player-state backends, distributed high-performance cache | Own mechanism | ✅ | Switches freely between strong-consistency and high-availability modes via config |
| YugabyteDB | CP / EC | Distributed relational (ACID) | Mission-critical apps needing ACID + cloud-native scalability, high-performance retail/global e-commerce backends, multi-region-resilient financial systems, legacy DB migration (Oracle, PostgreSQL) to distributed architecture | Raft | ❌ | Does not support eventual consistency |

Source: internal team reference table (Miro board), transcribed 2026-07-03.
