$nodes = @(
    @{ Name = "Slave1"; IP = "10.184.79.207" },
    @{ Name = "Slave2"; IP = "10.184.79.48" }
)

foreach ($node in $nodes) {

    $online = Test-Connection `
        -ComputerName $node.IP `
        -Count 2 `
        -Quiet

    if ($online) {
        Write-Host "$($node.Name) [$($node.IP)] : ONLINE"
    }
    else {
        Write-Host "$($node.Name) [$($node.IP)] : OFFLINE"
    }
}