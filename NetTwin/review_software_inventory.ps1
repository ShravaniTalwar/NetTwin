
$inventory = "C:\NetTwin\software_inventory.csv"
$output = "C:\NetTwin\software_review.csv"

if (!(Test-Path $inventory)) {
    throw "Software inventory not found: $inventory"
}

$results = foreach ($item in (Import-Csv $inventory)) {
    $reason = "Routine review"
    $priority = "NORMAL"

    if ($item.Name -match 'Chrome|Microsoft Edge|Firefox') {
        $priority = "HIGH"
        $reason = "Browser: verify against current vendor security releases"
    }
    elseif ($item.Name -match 'Java.*Development Kit|JDK') {
        $priority = "HIGH"
        $reason = "Java JDK: verify support lifecycle and security updates"
    }
    elseif ($item.Name -match '\.NET|Windows Desktop Runtime') {
        $priority = "HIGH"
        $reason = ".NET runtime: verify support status and installed patch level"
    }
    elseif ($item.Name -match 'MongoDB|Git|Visual Studio Code|Anaconda') {
        $priority = "REVIEW"
        $reason = "Verify installed version against vendor advisories"
    }

    [PSCustomObject]@{
        Node = $item.Node
        Name = $item.Name
        Version = $item.Version
        Publisher = $item.Publisher
        ReviewPriority = $priority
        ReviewReason = $reason
        VulnerabilityConfirmed = $false
    }
}

$results |
    Export-Csv -Path $output -NoTypeInformation -Encoding UTF8

Write-Host "Software review report created: $output"
$results |
    Group-Object ReviewPriority |
    Select-Object Name, Count |
    Format-Table -AutoSize
