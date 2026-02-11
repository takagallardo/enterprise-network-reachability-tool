# Enterprise Network Reachability & Service Verification Tool

A standardized server connectivity verification script designed for mixed OS enterprise environments.

---

## Overview

This script verifies server connectivity using actual service ports instead of ICMP (ping).

- Ubuntu → SSH (22)
- Windows → RDP (3389)

It focuses on real service availability rather than simple network presence.

---

## Purpose

Designed for infrastructure validation scenarios such as:

- Server relocation
- Post-maintenance verification
- Power outage recovery
- Mixed Windows / Linux environments

The script standardizes connectivity checks and generates structured output for reporting.

---

## Key Design Principles

- No ICMP dependency
- OS auto-detection
- Deterministic TCP verification
- Non-blocking execution
- Human-readable summary output
- CSV report generation for audit purposes

---

## Usage

Prepare `hostlist.txt` (one host per line):

```
IN-XXXXXXXX02
xh2XXXXXXXX-l
```

Run:

```
./check_hosts_nwcc.sh
```

---

## Output

- result_timestamp.txt
- result_timestamp.csv

---

## Security & Confidentiality

This repository contains a generalized implementation.

No internal infrastructure details or proprietary information are included.
