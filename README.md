# DataTrace

A job market analytics pipeline that pulls postings from public job board APIs, lands them in S3, models them in Postgres with dbt, and surfaces trends in Tableau.

Python ingestion → AWS Lambda (EventBridge) → S3 → RDS Postgres → dbt → Tableau Public

Sources: Greenhouse, Lever, RemoteOK, Arbeitnow public APIs.
