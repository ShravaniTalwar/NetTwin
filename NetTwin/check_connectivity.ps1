$nodes = @(
    @{
        Name = "Slave1"
        IP = "10.184.79.207"
    },
    @{
        Name = "Slave2"
        IP = "10.184.79.48"
    }
)

$outputFile = "C:\NetTwin\network_quality.csv"

# Create header if file doesn't exist
if (!(Test-Path $outputFile)) {
    "Timestamp,NODE,IP,PacketsSent,PacketsReceived,PacketLossPercent,MinLatencyMs,MaxLatencyMs,AverageLatencyMs,Status" |
        Set-Content $outputFile
}

foreach ($node in $nodes) {

    Write-Host ""
    Write-Host "Testing $($node.Name) [$($node.IP)]..." -ForegroundColor Cyan

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Send 10 ICMP packets
    $results = Test-Connection `
        -ComputerName $node.IP `
        -Count 10 `
        -ErrorAction SilentlyContinue

    $sent = 10
    $received = @($results).Count
    $lost = $sent - $received

    if ($sent -gt 0) {
        $lossPercent = ($lost / $sent) * 100
    }
    else {
        $lossPercent = 100
    }

    if ($received -gt 0) {

        $latencies = @(
            $results |
            ForEach-Object {
                [double]$_.ResponseTime
            }
        )

        $minLatency = ($latencies | Measure-Object -Minimum).Minimum
        $maxLatency = ($latencies | Measure-Object -Maximum).Maximum
        $avgLatency = ($latencies | Measure-Object -Average).Average

        $minLatency = [math]::Round($minLatency, 2)
        $maxLatency = [math]::Round($maxLatency, 2)
        $avgLatency = [math]::Round($avgLatency, 2)

        if ($lossPercent -eq 0) {
            $status = "GOOD"
        }
        elseif ($lossPercent -lt 20) {
            $status = "DEGRADED"
        }
        else {
            $status = "POOR"
        }

    }
    else {

        $minLatency = ""
        $maxLatency = ""
        $avgLatency = ""

        $status = "OFFLINE"
    }

    $line = @(
        $timestamp
        $node.Name
        $node.IP
        $sent
        $received
        ([math]::Round($lossPercent, 2))
        $minLatency
        $maxLatency
        $avgLatency
        $status
    ) -join ","

    Add-Content $outputFile $line

    Write-Host ""
    Write-Host "Packets Sent     : $sent"
    Write-Host "Packets Received : $received"
    Write-Host "Packet Loss      : $lossPercent %"

    if ($received -gt 0) {
        Write-Host "Min Latency      : $minLatency ms"
        Write-Host "Max Latency      : $maxLatency ms"
        Write-Host "Average Latency  : $avgLatency ms"
    }

    Write-Host "Status           : $status"

    if ($status -eq "GOOD") {
        Write-Host "Network quality is GOOD." -ForegroundColor Green
    }
    elseif ($status -eq "DEGRADED") {
        Write-Host "Network quality is DEGRADED." -ForegroundColor Yellow
    }
    else {
        Write-Host "Network quality is OFFLINE/POOR." -ForegroundColor Red
    }
}