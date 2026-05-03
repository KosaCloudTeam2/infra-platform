param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl
)

$healthUrl = "$BaseUrl/health"
$response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 10

if ($response.StatusCode -ne 200) {
    throw "Health check failed: $($response.StatusCode)"
}

Write-Host "Health check passed: $healthUrl"
