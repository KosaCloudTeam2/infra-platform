param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [int]$Requests = 100,
    [int]$Concurrency = 10
)

$jobs = @()
for ($i = 0; $i -lt $Requests; $i++) {
    while (($jobs | Where-Object { $_.State -eq "Running" }).Count -ge $Concurrency) {
        Start-Sleep -Milliseconds 100
        $jobs = $jobs | Where-Object { $_.State -eq "Running" }
    }

    $jobs += Start-Job -ScriptBlock {
        param($TargetUrl)
        try {
            Invoke-WebRequest -Uri $TargetUrl -UseBasicParsing -TimeoutSec 5 | Select-Object StatusCode
        } catch {
            $_.Exception.Message
        }
    } -ArgumentList $Url
}

Wait-Job $jobs | Out-Null
Receive-Job $jobs
Remove-Job $jobs
