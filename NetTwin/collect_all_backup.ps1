while ($true) {
$nodes = @(
    @{
        Name = "Slave1"
        IP = ""
        Username = ""
    },
    @{
        Name = "Slave2"
        IP = ""
        Username = ""
    }
)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

foreach ($node in $nodes) {

    Write-Host ""
    Write-Host "Collecting from $($node.Name)..."

    $target = "$($node.Username)@$($node.IP)"

    $data = ssh -i "$env:USERPROFILE\.ssh\id_ed25519" `
        -o IdentitiesOnly=yes `
        $target `
        "powershell.exe -ExecutionPolicy Bypass -File C:\NetTwinMonitor.ps1"

    $record = [ordered]@{
        Timestamp = $timestamp
        Node      = $node.Name
        IP        = $node.IP
    }

    foreach ($line in $data) {
        if ($line -match "^([^=]+)=(.*)$") {
            $record[$matches[1]] = $matches[2]
        }
    }

    [PSCustomObject]$record |
    Export-Csv "C:\NetTwin\network_data.csv" -Append -NoTypeInformation
}
    Start-Sleep -Seconds 10
}
