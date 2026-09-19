# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project status

This repository is currently empty — no source code, build tooling, or git history exists yet. Update this file once the project's language, framework, and structure are established.

## Commands

_To be added (build, lint, test, running a single test)._

# Job Market Analytics Pipeline

I'm a UC Davis Data Science student (rising 2nd year) building this as a 
portfolio project for Data Analyst / Data Engineer roles. Learning by 
building — give real code and commands, not conceptual explanations unless 
I ask.

## Stack
Python (ingestion) → AWS Lambda (EventBridge schedule) → S3 (raw landing) 
→ RDS Postgres (warehouse) → dbt (staging → marts) → SQL analysis → 
Tableau Public (dashboard)

## Sources
Greenhouse, Lever, Ashby, SmartRecruiters and Rippling public JSON APIs, plus
RemoteOK. Workday, iCIMS, Oracle and similar enterprise ATSs are out of scope
(no clean public API). US jobs only —
raw lands unfiltered, US filter happens in dbt staging. Arbeitnow dropped
(EU-only board). No scraping LinkedIn/Indeed.

## Working rules
- Write code like a competent human under normal time pressure — clean, 
  minimal comments only where logic needs explaining. No comment-per-line, 
  no decorative section dividers, no emoji in code or commits.
- Flag AWS free-tier limits and real dollar cost risk before running 
  anything that could incur charges.
- Be direct about what's wrong or fragile in my code/SQL — don't soften it.
- Flag whether a design choice is resume-defensible (I could explain it in 
  an interview) or cargo-culted.
- Build incrementally: ingestion script → Lambda wrapper → S3 → RDS → dbt 
  → Tableau. Don't jump ahead unless I ask.