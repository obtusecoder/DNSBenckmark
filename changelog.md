# Changelog

## [2.1] - dnsbenchmark.ps1

### Fixed
- **IPv6 Issue**: IPv6 benchmark wouldn't run if the local DNS entered was incorret/unsupported/wrong.
- **Global IPv6**: Instead of passing a single $hasIPv6 flag to every thread based only on local DNS behavior, each DNS provider should evaluate or test IPv6 support independently (or test AAAA records regardless and report failures if IPv6 resolution fails for whatever reason).

## [2.0.0] - dnsbenchmark.ps1

### Added
- **Dual Stack Testing (IPv4 & IPv6)**: Added full benchmarking for both IPv4 (`A` records) and IPv6 (`AAAA` records).
- **Network Capability Detection**: Added `Test-IPv6Support` function to dynamically verify IPv6 resolution support on the local network before running dual stack tests.
- **IPv6 Preheating**: Updated local cache preheating routine to execute `AAAA` lookups alongside `A` lookups when IPv6 is enabled.
- **Latency Distribution Bucketing**: Added automated latency grouping (`<20ms`, `20-50ms`, `50-100ms`, and `Failed`) in exported text reports.
- **Slowest Queries Reporting**: Implemented filtering and sorting to isolate queries taking longer than 50ms in exported summaries.

### Changed
- **Script Engine & Multi-Threading**: Converted `$BenchmarkServerBlock` to a script block executing via `$script:BenchmarkServerBlock` inside parallel `ThreadJob` instances.
- **Metrics Calculation**: Expanded return data to track separate average response times for IPv4 (`AvgIPv4`), IPv6 (`AvgIPv6`), and `CombinedAvg`.
- **Console Table Layout**: Expanded the primary console results table from 3 columns to 5 columns (`DNS Provider`, `IPv4 (A)`, `IPv6 (AAAA)`, `Combined Avg`, `Success`).
- **Export Report Structure**: Completely overhauled text file exports. Replaced raw line-by-line domain dumps with a structured summary featuring a Ranked Leaderboard, Failures Section, and Response Time Distribution.
- **Filename Changed**: Changed the file name to dnsbenchmark (now dnsbenchmark_v2) to refelct the purpose of the script better.
- 
### Fixed
- **Encoding & Formatting Standard**: Standardized output formatting and ASCII character usage (`-`) across all exported sections to eliminate UTF-8/ANSI encoding artifacts (`â€¢`) in text editors. It was annoying.

---

## [1.0.0] - dnstest.ps1

### Initial Features
- Basic multi-threaded DNS benchmarking for IPv4 (`A` records).
- Interactive user prompt for Local DNS IP input.
- Local DNS cache preheating before benchmark execution.
- Query timeout handling and failure tracking (>100ms threshold).
- Uniform domain shuffling (`Get-Random`) across parallel thread runs.
- Console results output table and raw domain log text file export.
