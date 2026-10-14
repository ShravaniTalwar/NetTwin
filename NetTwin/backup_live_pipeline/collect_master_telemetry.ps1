$ErrorActionPreference = "Stop"

$root = "C:\NetTwin"
$outFile = Join-Path $root "master_telemetry.csv"
$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$cpu = (Get-CimInstance Win32_Processor |
    Measure-Object -Property LoadPercentage -Average).Average

$os = Get-CimInstance Win32_OperatingSystem
$ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$ramFree = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$ramUsed = [math]::Round($ramTotal - $ramFree, 2)

$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$diskTotal = [math]::Round($disk.Size / 1GB, 2)
$diskFree = [math]::Round($disk.FreeSpace / 1GB, 2)

$adapter = Get-NetAdapter |
    Where-Object { $_.Name -eq "Wi-Fi" } |
    Select-Object -First 1

$firewallProfiles = Get-NetFirewallProfile
$firewallState = if (
    @($firewallProfiles | Where-Object { -not $_.Enabled }).Count -eq 0
) { "ENABLED" } else { "DISABLED" }

$defenderState = "UNKNOWN"
try {
    $defender = Get-MpComputerStatus
    if ($defender.RealTimeProtectionEnabled) {
        $defenderState = "ACTIVE"
    } else {
        $defenderState = "INACTIVE"
    }
} catch {}

$ports = @(
    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty LocalPort -Unique |
        Sort-Object
) -join ";"

$ramUsedPercent = if ($ramTotal -gt 0) {
    [math]::Round(($ramUsed / $ramTotal) * 100, 2)
} else { 0 }

$diskUsedPercent = if ($diskTotal -gt 0) {
    [math]::Round((($diskTotal - $diskFree) / $diskTotal) * 100, 2)
} else { 0 }

$row = [PSCustomObject]@{
    Timestamp = $now
    NODE = "Master"
    HOSTNAME = $env:COMPUTERNAME
    IP_ADDRESS = (
        Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Wi-Fi" `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike "169.254.*" -and
            $_.IPAddress -ne "127.0.0.1"
        } |
        Select-Object -First 1 -ExpandProperty IPAddress
    )
    CPU = $cpu
    RAM_TOTAL_GB = $ramTotal
    RAM_FREE_GB = $ramFree
    RAM_USED_GB = $ramUsed
    RAM_USED_PERCENT = $ramUsedPercent
    DISK_TOTAL_GB = $diskTotal
    DISK_FREE_GB = $diskFree
    DISK_USED_PERCENT = $diskUsedPercent
    NETWORK = $adapter.Name
    LINK_SPEED = [string]$adapter.LinkSpeed
    ADAPTER_STATUS = [string]$adapter.Status
    LISTENING_PORTS = $ports
    FIREWALL = $firewallState
    DEFENDER_REALTIME = $defenderState
}

if (Test-Path $outFile) {
    $row | Export-Csv $outFile -NoTypeInformation -Append
} else {
    $row | Export-Csv $outFile -NoTypeInformation
}

$row | Format-List
Write-Host "Master telemetry saved to $outFile"
