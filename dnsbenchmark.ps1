# Check and install the required ThreadJob module if missing
if (-not (Get-Module -ListAvailable -Name ThreadJob)) {
    Write-Host "ThreadJob module not detected. Attempting automatic installation..." -ForegroundColor Yellow
    try {
        Install-Module -Name ThreadJob -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
        Import-Module -Name ThreadJob -ErrorAction Stop
        Write-Host "Successfully installed and imported ThreadJob module.`n" -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Automatic installation failed. Details: $_" -ForegroundColor Red
        Write-Host "The script requires the ThreadJob module to execute parallel testing."
        Write-Host "Please run PowerShell as Administrator and execute: Install-Module ThreadJob"
        return
    }
}

# Public servers
$DnsServers = [ordered]@{
    "Cloudflare Pri" = "1.1.1.1"
    "Cloudflare Sec" = "1.0.0.1"
    "Google DNS Pri" = "8.8.8.8"
    "Google DNS Sec" = "8.8.4.4"
    "Quad 9"         = "9.9.9.9"
    "OpenDNS"        = "208.67.222.222"
}

# Domains to test
$Domains = @(
    # Search & Global
    "google.co.uk", "google.com", "youtube.com", "wikipedia.org", "bing.com",
    "duckduckgo.com", "yahoo.com", "live.com", "microsoft.com", "apple.com", "cloudflare.com", "quad9.net", "opendns.com",
    
    # Social & Community
    "facebook.com", "instagram.com", "x.com", "reddit.com", "linkedin.com",
    "pinterest.com", "tiktok.com", "whatsapp.com", "discord.com", "nextdoor.co.uk",
    
    # UK News & Media
    "bbc.co.uk", "bbc.com", "theguardian.com", "dailymail.co.uk", "telegraph.co.uk",
    "independent.co.uk", "sky.com", "itv.com", "channel4.com", "ft.com",
    "thesun.co.uk", "mirror.co.uk", "standard.co.uk", "manchestereveningnews.co.uk", "express.co.uk",
    
    # UK Government, Health & Education
    "gov.uk", "nhs.uk", "nidirect.gov.uk", "gov.scot", "parliament.uk",
    "open.ac.uk", "cambridge.org", "ox.ac.uk", "ucas.com", "st-andrews.ac.uk",
    
    # Shopping & Retail (UK Focused)
    "amazon.co.uk", "ebay.co.uk", "argos.co.uk", "tesco.com", "asda.com",
    "sainsburys.co.uk", "next.co.uk", "johnlewis.com", "boots.com", "currys.co.uk",
    "marksandspencer.com", "diy.com", "screwfix.com", "wickes.co.uk", "sportsdirect.com",
    "etsy.com", "temu.com", "shein.com", "aliexpress.com", "hm.com",
    
    # UK Property & Motors
    "rightmove.co.uk", "zoopla.co.uk", "onthemarket.com", "autotrader.co.uk", "motors.co.uk",
    
    # Finance & Banking (UK Large)
    "barclays.co.uk", "halifax.co.uk", "lloydsbank.com", "natwest.com", "hsbc.co.uk",
    "santander.co.uk", "nationwide.co.uk", "monzo.com", "paypal.com", "moneysavingexpert.com",
    
    # Travel & Transport (UK Focused)
    "trainline.com", "booking.com", "tfl.gov.uk", "nationalrail.co.uk", "tripadvisor.co.uk",
    "airbnb.co.uk", "easyjet.com", "britishairways.com", "uber.com", "premierinn.com",
    
    # Entertainment, Tech & Utility
    "netflix.com", "spotify.com", "disneyplus.com", "skysports.com", "roblox.com",
    "steampowered.com", "twitch.tv", "github.com", "stackoverflow.com", "fandom.com"
)

function Get-LocalDns {
    while ($true) {
        $userInput = (Read-Host "Enter your Local DNS Server IP address (e.g., 192.168.1.254)").Trim()
        if ([System.Net.IPAddress]::TryParse($userInput, [ref]$null)) {
            return $userInput
        } else {
            Write-Host "Error: Invalid IP address format. Please try again.`n" -ForegroundColor Red
        }
    }
}

function Test-DnsConnectivity {
    param ([string]$IP)
    try {
        $null = Resolve-DnsName -Name "google.com" -Type A -Server $IP -QuickTimeout -ErrorAction Stop
        return $true
    }
    catch {
        if ($_.Exception.Message -match "DNS_ERROR_RCODE_NAME_ERROR" -or $_.Exception.Message -match "does not exist") {
            return $true
        }
        return $false
    }
}

function Test-IPv6Support {
    param ([string]$IP)
    try {
        $null = Resolve-DnsName -Name "google.com" -Type AAAA -Server $IP -QuickTimeout -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

$BenchmarkServerBlock = {
    param (
        [string]$Name,
        [string]$IP,
        [string[]]$DomainList,
        [bool]$IsAlive = $true,
        [bool]$EnableIPv6 = $true
    )

    if (-not $IsAlive) {
        return [PSCustomObject]@{
            Name            = $Name
            AvgIPv4         = [double]::PositiveInfinity
            AvgIPv6         = [double]::PositiveInfinity
            CombinedAvg     = [double]::PositiveInfinity
            SuccessRate     = 0.0
            Failures        = @(@{ Domain = "ALL DOMAINS"; Reason = "DNS server unreachable" })
            DetailedLogs    = @(@{ Domain = "ALL DOMAINS"; RecordType = "ALL"; Status = "Fail"; Latency = "Unreachable"; RawMs = [double]::PositiveInfinity })
        }
    }

    $recordTypes = if ($EnableIPv6) { @("A", "AAAA") } else { @("A") }
    
    $v4Times = @()
    $v6Times = @()
    $totalSuccessfulQueries = 0
    $totalPossibleQueries = $DomainList.Count * $recordTypes.Count
    $serverFailures = @()
    $detailedLogs = @()

    foreach ($domain in $DomainList) {
        foreach ($type in $recordTypes) {
            $attempts = 0
            $success = $false
            $lastMs = 0
            $lastError = ""

            while ($attempts -lt 2 -and -not $success) {
                $attempts++
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $null = Resolve-DnsName -Name $domain -Type $type -Server $IP -QuickTimeout -ErrorAction Stop
                    $stopwatch.Stop()
                    
                    $lastMs = $stopwatch.Elapsed.TotalMilliseconds
                    if ($lastMs -le 100) { $success = $true } else { $lastError = ">100ms ({0:N2} ms)" -f $lastMs }
                }
                catch [System.Management.Automation.MethodInvocationException], [System.Net.NetworkInformation.PingException] {
                    $lastError = "Timeout/Network Error"
                }
                catch {
                    if ($_.Exception.Message -match "DNS_ERROR_RCODE_NAME_ERROR" -or $_.Exception.Message -match "does not exist") {
                        $lastError = "NXDOMAIN (Not Found)"
                        $attempts = 2
                    } else {
                        $lastError = "Error"
                    }
                }
            }

            if ($success) {
                if ($type -eq "A") { $v4Times += $lastMs } else { $v6Times += $lastMs }
                $totalSuccessfulQueries++
                $detailedLogs += @{ Domain = $domain; RecordType = $type; Status = "Success"; Latency = ("{0:N2} ms" -f $lastMs); RawMs = $lastMs }
            } else {
                $serverFailures += @{ Domain = "$domain ($type)"; Reason = $lastError }
                $detailedLogs += @{ Domain = $domain; RecordType = $type; Status = "Fail"; Latency = if ($lastMs -gt 0) { "{0:N2} ms" -f $lastMs } else { "--" }; RawMs = [double]::PositiveInfinity }
            }
        }
    }
    
    $avgV4 = if ($v4Times.Count -gt 0) { ($v4Times | Measure-Object -Average).Average } else { [double]::PositiveInfinity }
    $avgV6 = if ($v6Times.Count -gt 0) { ($v6Times | Measure-Object -Average).Average } else { [double]::PositiveInfinity }
    
    $allTimes = $v4Times + $v6Times
    $combinedAvg = if ($allTimes.Count -gt 0) { ($allTimes | Measure-Object -Average).Average } else { [double]::PositiveInfinity }
    $successRate = ($totalSuccessfulQueries / $totalPossibleQueries) * 100
    
    return [PSCustomObject]@{
        Name         = $Name
        AvgIPv4      = $avgV4
        AvgIPv6      = $avgV6
        CombinedAvg  = $combinedAvg
        SuccessRate  = $successRate
        Failures     = $serverFailures
        DetailedLogs = $detailedLogs
    }
}

function main {
    Write-Host "============================================================"
    Write-Host "                DNS BENCHMARK TOOL v2.1"
    Write-Host "============================================================"
    Write-Host "DISCLAIMER & INFO:"
    Write-Host "This script measures and compares DNS query latency (response times)"
    Write-Host "between your local server and major public DNS providers."
    Write-Host ""
    Write-Host "- Tests both IPv4 (A) and IPv6 (AAAA) resolution performance."
    Write-Host "- Queries taking longer than 100ms are marked as failures."
    Write-Host "- Run order is randomized to prevent network bias."
    Write-Host "- Upstream runs execute simultaneously to ensure network equity."
    Write-Host "- No data is sent or logged outside of your local machine."
    Write-Host "============================================================`n"

    $localDnsIp = Get-LocalDns
    
    Write-Host "`nVerifying Local DNS server status..." -ForegroundColor Gray
    $localIsAlive = Test-DnsConnectivity -IP $localDnsIp
    $localHasIPv6 = $false

    if (-not $localIsAlive) {
        Write-Host "Warning: Local DNS server ($localDnsIp) is not responsive." -ForegroundColor Yellow
        Write-Host "Local DNS will be marked as "Failed" in results." -ForegroundColor Red
    } else {
        Write-Host "Checking IPv6 (AAAA) capability on local network..." -ForegroundColor Gray
        $localHasIPv6 = Test-IPv6Support -IP $localDnsIp
        if ($localHasIPv6) {
            Write-Host "Local DNS: IPv6 (AAAA) records supported." -ForegroundColor Green
        } else {
            Write-Host "Local DNS: IPv6 lookup failed or not supported." -ForegroundColor Red
        }

        Write-Host "Preheating Local DNS Cache ($($Domains.Count) domains)..." -ForegroundColor Gray
        $jobs = foreach ($domain in $Domains) {
            Start-ThreadJob -ScriptBlock {
                param($d, $ip, $v6)
                $null = Resolve-DnsName -Name $d -Type A -Server $ip -QuickTimeout -ErrorAction SilentlyContinue
                if ($v6) {
                    $null = Resolve-DnsName -Name $d -Type AAAA -Server $ip -QuickTimeout -ErrorAction SilentlyContinue
                }
            } -ArgumentList $domain, $localDnsIp, $localHasIPv6
        }
        $null = Wait-Job -Job $jobs
        $jobs | Remove-Job
    }

    # Verify global public IPv6 support using Google DNS (8.8.8.8) independently
    Write-Host "Testing global IPv6 (AAAA) lookup capability via Public DNS..." -ForegroundColor Gray
    $publicIPv6Supported = Test-IPv6Support -IP "8.8.8.8"
    if ($publicIPv6Supported) {
        Write-Host "Public DNS IPv6 benchmarks: Enabled." -ForegroundColor Green
    } else {
        Write-Host "Public DNS IPv6 benchmarks: Disabled (No local network IPv6 stack detected)." -ForegroundColor Yellow
    }

    $FinalDnsServers = [ordered]@{ "Local DNS" = $localDnsIp }
    foreach ($key in $DnsServers.Keys) { $FinalDnsServers[$key] = $DnsServers[$key] }

    # Uniform shuffling
    $UniformShuffledDomains = $Domains | Get-Random -Count $Domains.Count

    $results = @()
    $allFailures = @{}

    Write-Host "`nStarting Multi Threaded Benchmark...`n" -ForegroundColor Cyan

    $benchJobs = foreach ($name in $FinalDnsServers.Keys) {
        $ip = $FinalDnsServers[$name]
        
        if ($name -eq "Local DNS") {
            $isServerAlive = $localIsAlive
            $serverEnableIPv6 = $localHasIPv6
        } else {
            $isServerAlive = $true
            $serverEnableIPv6 = $publicIPv6Supported
        }
        
        Write-Host "Starting benchmark thread for: $name ($ip)" -ForegroundColor Gray
        Start-ThreadJob -ScriptBlock $script:BenchmarkServerBlock -ArgumentList $name, $ip, $UniformShuffledDomains, $isServerAlive, $serverEnableIPv6
    }

    Write-Host "`nRunning benchmark..." -ForegroundColor Yellow
    $benchResults = Wait-Job -Job $benchJobs | Receive-Job
    $benchJobs | Remove-Job

    foreach ($bench in $benchResults) {
        $results += $bench
        if ($bench.Failures.Count -gt 0) {
            $allFailures[$bench.Name] = $bench.Failures | Sort-Object { $_.Domain }
        }
    }

    # Main Console Output Table
    $consoleOutput = "`n" + ("="*68) + "`n"
    $consoleOutput += ("{0,-15} | {1,-12} | {2,-12} | {3,-12} | {4,-10}" -f "DNS Provider", "IPv4 (A)", "IPv6 (AAAA)", "Combined Avg", "Success") + "`n"
    $consoleOutput += ("="*68) + "`n"

    $sortedResults = $results | Sort-Object CombinedAvg

    foreach ($res in $sortedResults) {
        $v4Str = if ($res.AvgIPv4 -ne [double]::PositiveInfinity) { "{0:N2} ms" -f $res.AvgIPv4 } else { "Failed" }
        $v6Str = if ($res.AvgIPv6 -ne [double]::PositiveInfinity) { "{0:N2} ms" -f $res.AvgIPv6 } else { "N/A" }
        $combStr = if ($res.CombinedAvg -ne [double]::PositiveInfinity) { "{0:N2} ms" -f $res.CombinedAvg } else { "Failed" }
        $successStr = "{0:N1}%" -f $res.SuccessRate

        $consoleOutput += ("{0,-15} | {1,-12} | {2,-12} | {3,-12} | {4,-10}" -f $res.Name, $v4Str, $v6Str, $combStr, $successStr) + "`n"
    }
    $consoleOutput += ("="*68) + "`n"

    # Console Failures Section
    $consoleOutput += "`n" + ("="*68) + "`n"
    $consoleOutput += "FAILURES REPORT BY SERVER`n"
    $consoleOutput += ("="*68) + "`n"

    if ($allFailures.Count -gt 0) {
        foreach ($serverName in $allFailures.Keys) {
            $consoleOutput += "`n[ $serverName ]`n"
            $consoleOutput += ("  {0,-30} | {1,-32}" -f "Domain (Record)", "Reason") + "`n"
            $consoleOutput += ("  " + "-"*64) + "`n"
            foreach ($fail in $allFailures[$serverName]) {
                $consoleOutput += ("  {0,-30} | {1,-32}" -f $fail.Domain, $fail.Reason) + "`n"
            }
        }
    } else {
        $consoleOutput += "`nAll responsive servers successfully resolved 100% of queries.`n"
    }
    $consoleOutput += "`n" + ("="*68)

    Write-Host $consoleOutput

    # Export Prompt
    Write-Host ""
    $exportChoice = (Read-Host "Would you like to export these results to a text file? (Y/N)").ToUpper().Trim()
    
    if ($exportChoice -eq "Y" -or $exportChoice -eq "YES") {
        $defaultDirectory = [Environment]::GetFolderPath("Desktop")
        Write-Host "`nEnter target save directory path."
        $userDirectory = (Read-Host "Press ENTER to accept default folder ($defaultDirectory)").Trim()
        
        $targetDirectory = if ([string]::IsNullOrWhiteSpace($userDirectory)) { $defaultDirectory } else { $userDirectory }
        
        if (-not (Test-Path -Path $targetDirectory -PathType Container)) {
            Write-Host "`nError: Target directory does not exist. Export aborted." -ForegroundColor Red
            return
        }

        $timestamp = Get-Date -Format "ddMMyyyy_HHmmss"
        $fileName = "dns_benchmark_results_$timestamp.txt"
        $finalDestinationPath = [System.IO.Path]::Combine($targetDirectory, $fileName)
        
        # Formatted Compact Report
        $winner = $sortedResults[0]
        $winnerAvgText = if ($winner.CombinedAvg -ne [double]::PositiveInfinity) { "{0:N2} ms avg" -f $winner.CombinedAvg } else { "N/A (All providers failed)" }
        $timestampFormatted = Get-Date -Format "dd/MM/yyyy HH:mm:ss"

        $fileOutput  = "================================================================================`n"
        $fileOutput += "                      DNS BENCHMARK SUMMARY`n"
        $fileOutput += "================================================================================`n"
        $fileOutput += "  Date/Time          : $timestampFormatted`n"
        $fileOutput += "  Domains Tested     : $($Domains.Count)`n"
        $fileOutput += "  Local DNS IPv6     : $(if ($localHasIPv6) { 'Enabled' } else { 'Disabled/Unsupported' })`n"
        $fileOutput += "  Public DNS IPv6    : $(if ($publicIPv6Supported) { 'Enabled' } else { 'Disabled' })`n"
        $fileOutput += "  Fastest Resolver   : $($winner.Name) ($winnerAvgText)`n"
        $fileOutput += "================================================================================`n`n"

        $fileOutput += "--------------------------------------------------------------------------------`n"
        $fileOutput += " 1. OVERALL LEADERBOARD`n"
        $fileOutput += "--------------------------------------------------------------------------------`n"
        $fileOutput += ("{0,-6} | {1,-18} | {2,-11} | {3,-11} | {4,-11} | {5,-10}" -f "Rank", "DNS Provider", "IPv4 (A)", "IPv6 (AAAA)", "Combined", "Success") + "`n"
        $fileOutput += "--------------------------------------------------------------------------------`n"

        $rank = 1
        foreach ($res in $sortedResults) {
            $v4Str = if ($res.AvgIPv4 -ne [double]::PositiveInfinity) { "{0:N2} ms" -f $res.AvgIPv4 } else { "Failed" }
            $v6Str = if ($res.AvgIPv6 -ne [double]::PositiveInfinity) { "{0:N2} ms" -f $res.AvgIPv6 } else { "N/A" }
            $combStr = if ($res.CombinedAvg -ne [double]::PositiveInfinity) { "{0:N2} ms" -f $res.CombinedAvg } else { "Failed" }
            $successStr = "{0:N1}%" -f $res.SuccessRate

            $fileOutput += ("#{0,-5} | {1,-18} | {2,-11} | {3,-11} | {4,-11} | {5,-10}" -f $rank, $res.Name, $v4Str, $v6Str, $combStr, $successStr) + "`n"
            $rank++
        }
        $fileOutput += "--------------------------------------------------------------------------------`n`n"

        $fileOutput += "--------------------------------------------------------------------------------`n"
        $fileOutput += " 2. FAILURES SUMMARY`n"
        $fileOutput += "--------------------------------------------------------------------------------`n"

        if ($allFailures.Count -gt 0) {
            foreach ($serverName in $allFailures.Keys) {
                $fileOutput += "[ $serverName ]`n"
                foreach ($fail in $allFailures[$serverName]) {
                    $fileOutput += ("  - {0,-32} - {1}" -f $fail.Domain, $fail.Reason) + "`n"
                }
                $fileOutput += "`n"
            }
        } else {
            $fileOutput += "All servers resolved 100% of domains successfully.`n`n"
        }
        $fileOutput += "--------------------------------------------------------------------------------`n`n"

        $fileOutput += "================================================================================`n"
        $fileOutput += " 3. RESPONSE TIME & SLOWEST QUERIES (>50ms)`n"
        $fileOutput += "================================================================================`n"

        foreach ($res in $results) {
            $fileOutput += "`n[ PROVIDER: $($res.Name) ]`n"
            
            $under20 = ($res.DetailedLogs | Where-Object { $_.RawMs -lt 20 }).Count
            $between20and50 = ($res.DetailedLogs | Where-Object { $_.RawMs -ge 20 -and $_.RawMs -le 50 }).Count
            $between50and100 = ($res.DetailedLogs | Where-Object { $_.RawMs -gt 50 -and $_.RawMs -le 100 }).Count
            $failedCount = ($res.DetailedLogs | Where-Object { $_.Status -ne "Success" }).Count

            $fileOutput += "  Latency:`n"
            $fileOutput += "    -  < 20 ms   : $under20 queries`n"
            $fileOutput += "    - 20 - 50 ms : $between20and50 queries`n"
            $fileOutput += "    - 50 - 100ms : $between50and100 queries`n"
            $fileOutput += "    - Failed     : $failedCount queries`n`n"

            $slowQueries = $res.DetailedLogs | Where-Object { $_.RawMs -gt 50 -and $_.Status -eq "Success" } | Sort-Object -Property RawMs -Descending
            if ($slowQueries.Count -gt 0) {
                $fileOutput += "  Slowest Successful Resolves (>50ms):`n"
                $fileOutput += ("  " + "-"*56) + "`n"
                $fileOutput += ("  {0,-32} | {1,-8} | {2,-10}" -f "Domain", "Record", "Latency") + "`n"
                $fileOutput += ("  " + "-"*56) + "`n"
                foreach ($slow in $slowQueries) {
                    $fileOutput += ("  {0,-32} | {1,-8} | {2,-10}" -f $slow.Domain, $slow.RecordType, $slow.Latency) + "`n"
                }
            } else {
                $fileOutput += "  No slow queries (>50ms) detected for this provider.`n"
            }
            $fileOutput += "--------------------------------------------------------------------------------`n"
        }

        try {
            $fileOutput | Out-File -FilePath $finalDestinationPath -Encoding utf8
            Write-Host "`nSuccess: Exported report to:`n$finalDestinationPath" -ForegroundColor Green
        }
        catch {
            Write-Host "`nError: Could not write the file. Details: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "`nExiting without file export." -ForegroundColor Gray
    }
    Read-Host "Press Enter to Exit."
}

main
