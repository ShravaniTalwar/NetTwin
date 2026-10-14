
# ==========================================
# NetTwin - Consolidate Security Inventory
# Run on Master
# ==========================================

$nodes = @(
    @{
        Name = "Slave1"
        IP = "10.11.251.207"
        User = "Neha"
    },
    @{
        Name = "Slave2"
        IP = "10.11.251.48"
        User = "rushda"
    }
)

$outputDirectory = "C:\NetTwin"
$softwareFile = Join-Path $outputDirectory "software_inventory.csv"
$assessmentFile = Join-Path $outputDirectory "security_assessment.csv"

New-Item -ItemType Directory -Path $outputDirectory -Force |
    Out-Null

$allSoftware = @()
$assessments = @()

foreach ($node in $nodes) {
    Write-Host "Collecting security inventory from $($node.Name)..." `
        -ForegroundColor Cyan

    try {
        # Run the existing inventory script remotely.
        $target = "$($node.User)@$($node.IP)"
        $remoteOutput = @(
            ssh $target `
                "powershell -ExecutionPolicy Bypass -File C:\NetTwinSecurityInventory.ps1" 2>&1
        )

        if ($LASTEXITCODE -ne 0) {
            throw "SSH or remote inventory script failed."
        }

        # Parse key=value output.
        $values = @{}
        foreach ($line in $remoteOutput) {
            $text = [string]$line
            if ($text -match '^([A-Z_]+)=(.*)$') {
                $values[$matches[1]] = $matches[2]
            }
        }

        if (!$values.ContainsKey("SOFTWARE_COUNT")) {
            throw "Software count was not returned."
        }

        # Retrieve the remote CSV contents over SSH.
        # Convert the CSV to JSON remotely to preserve commas and quoting.
        $remoteJsonCommand = @'
$items = Import-Csv "C:\NetTwin\software_inventory.csv"
ConvertTo-Json -InputObject @($items) -Compress -Depth 4
'@

        $encodedCommand = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($remoteJsonCommand)
        )

        $jsonOutput = @(
            ssh $target `
                "powershell -NoProfile -EncodedCommand $encodedCommand" 2>&1
        )

        if ($LASTEXITCODE -ne 0) {
            throw "Could not read the remote software inventory."
        }

        $jsonText = $jsonOutput -join "`n"
        $items = @()

        if (-not [string]::IsNullOrWhiteSpace($jsonText)) {
            $parsed = ConvertFrom-Json -InputObject $jsonText
            if ($null -ne $parsed) {
                $items = @($parsed)
            }
        }

        foreach ($item in $items) {
            $allSoftware += [PSCustomObject]@{
                Node = $node.Name
                Hostname = [string]$item.Hostname
                Name = [string]$item.Name
                Version = [string]$item.Version
                Publisher = [string]$item.Publisher
                InventoryTimestamp = [string]$item.Timestamp
            }
        }

        $assessments += [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Node = $node.Name
            Hostname = $values["HOSTNAME"]
            SoftwareCountReported = $values["SOFTWARE_COUNT"]
            LastUpdateDate = $values["LAST_UPDATE_DATE"]
            WindowsUpdateStatus = $values["WINDOWS_UPDATE_STATUS"]
            AvailableUpdateCount = $values["AVAILABLE_UPDATE_COUNT"]
            CollectionStatus = "SUCCESS"
        }

        Write-Host "$($node.Name): inventory collected." `
            -ForegroundColor Green
    }
    catch {
        Write-Host "$($node.Name): collection failed - $_" `
            -ForegroundColor Red

        $assessments += [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Node = $node.Name
            Hostname = ""
            SoftwareCountReported = ""
            LastUpdateDate = ""
            WindowsUpdateStatus = "UNKNOWN"
            AvailableUpdateCount = "UNKNOWN"
            CollectionStatus = "FAILED"
        }
    }
}

# Save latest consolidated snapshots.
$allSoftware |
    Sort-Object Node, Name, Version -Unique |
    Export-Csv -Path $softwareFile -NoTypeInformation -Encoding UTF8

$assessments |
    Export-Csv -Path $assessmentFile -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "========================================"
Write-Host "NETTWIN SECURITY INVENTORY SUMMARY"
Write-Host "========================================"
$assessments |
    Format-Table Node, Hostname, SoftwareCountReported,
        WindowsUpdateStatus, AvailableUpdateCount, CollectionStatus -AutoSize

Write-Host "Software inventory: $softwareFile"
Write-Host "Security assessment: $assessmentFile"
