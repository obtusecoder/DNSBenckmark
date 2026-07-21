# DNS Benchmark Tool

## Reasons For Writing This Script
- **Lack of Options**: I had been looking for a DNS Benchmark program and couldn't find one that wasn't either a paid service/program or it lacked a feature I want.
- **Accuracy**: I wanted something that I knew the code too, and that I could be sure that it was accurate at the time of running the script.
- **Exporting**: I needed the ability to export the results and store them for reference later.

## Features

- **Automated Dependency Management**: Checks for the required `ThreadJob` module and attempts automatic installation (`Scope CurrentUser`) if it is missing.
- **Preheated Local Cache**: Automatically sends concurrent "preheat" queries to your local DNS server to populate its internal cache before running benchmarks, ensuring an accurate evaluation of cached response times.
- **Fair Testing Architecture**: 
  - Randomizes the list of domains uniformly to eliminate sequence and network caching bias.
  - Executes benchmarks across upstream providers concurrently via multi threading to ensure fair network conditions.
- **Strict Performance Filtering**: Queries with latencies exceeding **100ms** or resulting in errors/timeouts are explicitly tracked as failures.
- **Comprehensive Failure Breakdown**: Aggregates failures and reports them alphabetically by domain for straightforward analysis (e.g., Timeout, NXDOMAIN).
- **Export Options**: Saves summarized metrics along with granular, sorted per domain latency reports into a structured text document.

## Providers Evaluated

- **Local DNS** (User-specified IP)
- **Cloudflare** (Primary & Secondary: `1.1.1.1`, `1.0.0.1`)
- **Google DNS** (Primary & Secondary: `8.8.8.8`, `8.8.4.4`)
- **Quad9** (`9.9.9.9`)
- **OpenDNS** (`208.67.222.222`)

## Domain Test Suite

The benchmark evaluates **over 100 localized and global domains** spanning multiple industries to ensure balanced real world simulation:
- **Search & Infrastructure**: Google, YouTube, Wikipedia, Cloudflare, Bing
- **Social Media & Communities**: Facebook, Instagram, X (Twitter), Reddit, LinkedIn, Discord, WhatsApp
- **UK News & Media**: BBC, The Guardian, Daily Mail, Sky, Telegraph, Financial Times
- **UK Government, Health & Education**: GOV.UK, NHS.uk, Oxford, Cambridge, UCAS
- **UK Retail & E-commerce**: Amazon.co.uk, eBay, Argos, Tesco, Marks & Spencer, Temu, Etsy
- **Finance & Banking**: Barclays, Lloyds, Halifax, NatWest, Monzo, PayPal
- **Travel & Entertainment**: Trainline, Booking.com, National Rail, Netflix, Spotify, Steam

## Installation & Requirements

1. **Operating System**: Windows 10/11 or Windows Server running PowerShell 5.1+.
2. **Execution Policy**: Ensure your execution policy allows running local scripts:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```
3. **Dependencies**: The script utilizes the `ThreadJob` module. If the automatic installation fails due to permissions, open an elevated PowerShell prompt (Run as Administrator) and run:
   ```powershell
   Install-Module -Name ThreadJob -Force
   ```

## Usage

1. Clone or download the script file (e.g., `dnsbenchmark.ps1`).
2. Open PowerShell and execute the script:
   ```powershell
   .\dnsbenchmark.ps1
   ```
   - You can also run the script from Explorer.
3. Enter your Local DNS Server IP address when prompted (e.g., `192.168.1.254` or `10.0.0.1`).
4. Wait for the Benchmark to complete. This usually takes less than 30 seconds.
5. Choose whether to export the detailed logs to a plain text file on your Desktop or a custom path.

## Console Output Preview

```text
====================================================================
DNS Provider    | IPv4 (A)     | IPv6 (AAAA)  | Combined Avg | Success   
====================================================================
Local DNS       | 2.14 ms      | 3.10 ms      | 2.62 ms      | 100.0%    
Cloudflare Pri  | 12.45 ms     | 14.20 ms     | 13.33 ms     | 100.0%    
Google DNS Pri  | 18.20 ms     | 19.10 ms     | 18.65 ms     | 100.0%    
Quad 9          | 21.05 ms     | 22.40 ms     | 21.73 ms     | 99.0%     
OpenDNS         | 24.10 ms     | N/A          | 24.10 ms     | 100.0%    
====================================================================

====================================================================
FAILURES REPORT BY SERVER
====================================================================

[ Quad 9 ]
  Domain (Record)                | Reason                          
  ------------------------------------------------------------------
  some-unstable-domain.com (AAAA)| >100ms (112.50 ms)
```

## Export File Preview
```
================================================================================
                      DNS BENCHMARK SUMMARY
================================================================================
  Date/Time          : 21/07/2026 13:36:01
  Domains Tested     : 100
  IPv6 Mode          : Enabled (A & AAAA Records)
  Fastest Resolver   : Local DNS (2.62 ms avg)
================================================================================

--------------------------------------------------------------------------------
 1. OVERALL LEADERBOARD
--------------------------------------------------------------------------------
Rank   | DNS Provider       | IPv4 (A)    | IPv6 (AAAA) | Combined    | Success   
--------------------------------------------------------------------------------
#1     | Local DNS          | 2.14 ms     | 3.10 ms     | 2.62 ms     | 100.0%    
#2     | Cloudflare Pri     | 12.45 ms    | 14.20 ms    | 13.33 ms    | 100.0%    
--------------------------------------------------------------------------------

================================================================================
 3. RESPONSE TIME & SLOWEST QUERIES (>50ms)
================================================================================

[ PROVIDER: Local DNS ]
  Latency:
    -  < 20 ms   : 198 queries
    - 20 - 50 ms : 2 queries
    - 50 - 100ms : 0 queries
    - Failed     : 0 queries

  No slow queries (>50ms) detected for this provider.
--------------------------------------------------------------------------------
```

## Security & Privacy Notice

- **Completely Local**: No telemetry, analytics, or metric data is transmitted outside your local machine.
