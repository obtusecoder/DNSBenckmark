# Auto-check and install the required ThreadJob module if missing
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

# Public servers separated explicitly to prevent array-passing bugs in multi-threading
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

function Benchmark-Server {
    param (
        [string]$Name,
        [string]$IP,
        [string[]]$DomainList,
        [bool]$IsAlive = $true
    )

    if (-not $IsAlive) {
        return [PSCustomObject]@{
            Name         = $Name
            AvgTime      = [double]::PositiveInfinity
            SuccessRate  = 0.0
            Failures     = @(@{ Domain = "ALL DOMAINS"; Reason = "DNS server unreachable or does not exist" })
            DetailedLogs = @(@{ Domain = "ALL DOMAINS"; Status = "Fail"; Latency = "Unreachable"; RawMs = [double]::PositiveInfinity })
        }
    }

    $totalTime = 0
    $successfulQueries = 0
    $serverFailures = @()
    $detailedLogs = @()

    foreach ($domain in $DomainList) {
        $attempts = 0
        $success = $false
        $lastMs = 0
        $lastError = ""

        while ($attempts -lt 2 -and -not $success) {
            $attempts++
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $null = Resolve-DnsName -Name $domain -Type A -Server $IP -QuickTimeout -ErrorAction Stop
                $stopwatch.Stop()
                
                $lastMs = $stopwatch.Elapsed.TotalMilliseconds
                # Changed from 150ms threshold down to 100ms threshold
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
            $totalTime += $lastMs
            $successfulQueries++
            $detailedLogs += @{ Domain = $domain; Status = "Success"; Latency = ("{0:N2} ms" -f $lastMs); RawMs = $lastMs }
        } else {
            $serverFailures += @{ Domain = $domain; Reason = $lastError }
            $detailedLogs += @{ Domain = $domain; Status = "Fail"; Latency = if ($lastMs -gt 0) { "{0:N2} ms" -f $lastMs } else { "--" }; RawMs = [double]::PositiveInfinity }
        }
    }
    
    $avgTime = if ($successfulQueries -gt 0) { $totalTime / $successfulQueries } else { [double]::PositiveInfinity }
    $successRate = ($successfulQueries / $DomainList.Count) * 100
    
    return [PSCustomObject]@{
        Name         = $Name
        AvgTime      = $avgTime
        SuccessRate  = $successRate
        Failures     = $serverFailures
        DetailedLogs = $detailedLogs
    }
}

function main {
    Write-Host "============================================================"
    Write-Host "                DNS BENCHMARK TOOL"
    Write-Host "============================================================"
    Write-Host "DISCLAIMER & INFO:"
    Write-Host "This script measures and compares DNS query latency (response times)"
    Write-Host "between your local server and major public DNS providers."
    Write-Host ""
    Write-Host "- It performs real-time 'A' record lookups against popular websites."
    Write-Host "- Queries taking longer than 100ms are marked as failures." # Updated description text
    Write-Host "- Run order is randomized uniformly to prevent network bias."
    Write-Host "- Upstream runs execute simultaneously to ensure network equity."
    Write-Host "- No data is sent or logged outside of your local machine."
    Write-Host "============================================================`n"

    $localDnsIp = Get-LocalDns
    
    Write-Host "`nVerifying Local DNS server status..." -ForegroundColor Gray
    $localIsAlive = Test-DnsConnectivity -IP $localDnsIp

    if (-not $localIsAlive) {
        Write-Host "Warning: Local DNS server ($localDnsIp) is not responsive." -ForegroundColor Yellow
    } else {
        Write-Host "Preheating Local DNS Cache ($($Domains.Count) domains)..." -ForegroundColor Gray
        $jobs = foreach ($domain in $Domains) {
            Start-ThreadJob -ScriptBlock {
                param($d, $ip)
                $null = Resolve-DnsName -Name $d -Type A -Server $ip -QuickTimeout -ErrorAction SilentlyContinue
            } -ArgumentList $domain, $localDnsIp
        }
        $null = Wait-Job -Job $jobs
        $jobs | Remove-Job
    }

    $FinalDnsServers = [ordered]@{ "Local DNS" = $localDnsIp }
    foreach ($key in $DnsServers.Keys) { $FinalDnsServers[$key] = $DnsServers[$key] }

    # Randomize the domains ONCE here so all threads test the exact same sequence fairly
    $UniformShuffledDomains = $Domains | Get-Random -Count $Domains.Count

    $results = @()
    $allFailures = @{}

    Write-Host "`nStarting Multi Threaded Benchmark...`n" -ForegroundColor Cyan

    $benchJobs = foreach ($name in $FinalDnsServers.Keys) {
        $ip = $FinalDnsServers[$name]
        $isServerAlive = if ($name -eq "Local DNS") { $localIsAlive } else { $true }
        
        Write-Host "Starting benchmark thread for: $name ($ip)" -ForegroundColor Gray
        Start-ThreadJob -ScriptBlock ${function:Benchmark-Server} -ArgumentList $name, $ip, $UniformShuffledDomains, $isServerAlive
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

    # Main Comparison Table Construction
    $consoleOutput = "`n" + ("="*50) + "`n"
    $consoleOutput += ("{0,-15} | {1,-15} | {2,-12}" -f "DNS Provider", "Avg Latency", "Success Rate") + "`n"
    $consoleOutput += ("="*50) + "`n"

    $sortedResults = $results | Sort-Object AvgTime

    foreach ($res in $sortedResults) {
        $latencyStr = if ($res.AvgTime -ne [double]::PositiveInfinity) { "{0:N2} ms" -f $res.AvgTime } else { "Failed" }
        $successStr = "{0:N1}%" -f $res.SuccessRate
        $consoleOutput += ("{0,-15} | {1,-15} | {2,-12}" -f $res.Name, $latencyStr, $successStr) + "`n"
    }
    $consoleOutput += ("="*50) + "`n"

    # Separated Failures Section Construction (Alphabetized by Domain)
    $consoleOutput += "`n" + ("="*50) + "`n"
    $consoleOutput += "FAILURES REPORT BY SERVER`n"
    $consoleOutput += ("="*50) + "`n"

    if ($allFailures.Count -gt 0) {
        foreach ($serverName in $allFailures.Keys) {
            $consoleOutput += "`n[ $serverName ]`n"
            $consoleOutput += ("  {0,-25} | {1,-40}" -f "Domain", "Reason") + "`n"
            $consoleOutput += ("  " + "-"*66) + "`n"
            foreach ($fail in $allFailures[$serverName]) {
                $consoleOutput += ("  {0,-25} | {1,-40}" -f $fail.Domain, $fail.Reason) + "`n"
            }
        }
    } else {
        $consoleOutput += "`nAll servers successfully resolved 100% of domains.`n"
    }
    $consoleOutput += "`n" + ("="*50)

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
        
        $fileOutput = "============================================================`n"
        $fileOutput += "                 DNS BENCHMARK REPORT SUMMARY`n"
        $fileOutput += "============================================================`n"
        $fileOutput += $consoleOutput + "`n`n"
        
        $fileOutput += "============================================================`n"
        $fileOutput += "            DETAILED METRICS PER TESTED DOMAIN`n"
        $fileOutput += "============================================================`n"
        
        foreach ($res in $results) {
            $fileOutput += "`n[ Detailed Results for: $($res.Name) ]`n"
            $fileOutput += ("{0,-35} | {1,-15} | {2,-15}" -f "Tested Domain", "Status", "Response Time") + "`n"
            $fileOutput += ("-" * 71) + "`n"
            
            $sortedLogs = $res.DetailedLogs | Sort-Object { $_.RawMs }
            foreach ($log in $sortedLogs) {
                $fileOutput += ("{0,-35} | {1,-15} | {2,-15}" -f $log.Domain, $log.Status, $log.Latency) + "`n"
            }
            $fileOutput += ("=" * 71) + "`n"
        }

        try {
            $fileOutput | Out-File -FilePath $finalDestinationPath -Encoding utf8
            Write-Host "`nSuccess: Exported file to:`n$finalDestinationPath" -ForegroundColor Green
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
