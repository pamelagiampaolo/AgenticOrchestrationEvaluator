[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PipeName,
    [Parameter(Mandatory)][string]$CandidateSid,
    [Parameter(Mandatory)][string]$CandidateIdentity,
    [Parameter(Mandatory)][string]$ReservedProbePath,
    [Parameter(Mandatory)][string]$ReportPath
)
$ErrorActionPreference = 'Stop'
$pipeSecurity = [IO.Pipes.PipeSecurity]::new()
$pipeSecurity.AddAccessRule([IO.Pipes.PipeAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-18'), [IO.Pipes.PipeAccessRights]::FullControl, [Security.AccessControl.AccessControlType]::Allow))
$pipeSecurity.AddAccessRule([IO.Pipes.PipeAccessRule]::new([Security.Principal.SecurityIdentifier]::new($CandidateSid), [IO.Pipes.PipeAccessRights]::ReadWrite, [Security.AccessControl.AccessControlType]::Allow))
$pipe = [IO.Pipes.NamedPipeServerStream]::new($PipeName, [IO.Pipes.PipeDirection]::InOut, 1, [IO.Pipes.PipeTransmissionMode]::Byte, [IO.Pipes.PipeOptions]::None, 4096, 4096, $pipeSecurity)
try {
    $pipe.WaitForConnection()
    $reader = [IO.StreamReader]::new($pipe, [Text.Encoding]::UTF8, $false, 4096, $true)
    $writer = [IO.StreamWriter]::new($pipe, [Text.UTF8Encoding]::new($false), 4096, $true)
    $writer.AutoFlush = $true
    $request = [ordered]@{ products = @([ordered]@{ productId = 'P-001'; name = 'Tastiera'; availableQuantity = 0 }, [ordered]@{ productId = 'P-002'; name = 'Mouse'; availableQuantity = 5 }, [ordered]@{ productId = 'P-003'; name = 'Monitor'; availableQuantity = 10 }); threshold = 5; reservedProbePath = $ReservedProbePath }
    $writer.WriteLine(($request | ConvertTo-Json -Depth 6 -Compress))
    $response = $reader.ReadLine() | ConvertFrom-Json
    $expected = @([ordered]@{ productId = 'P-001'; name = 'Tastiera'; availableQuantity = 0 })
    $queryPassed = (($response.queryResult | ConvertTo-Json -Depth 5 -Compress) -eq ($expected | ConvertTo-Json -Depth 5 -Compress))
    $reservedReadDenied = ($response.accessProbe.denied -eq $true -and [string]$response.accessProbe.code -in @('EACCES', 'EPERM'))
    $identityObserved = ([string]$response.identity).Trim().ToLowerInvariant()
    $identityPassed = ($identityObserved -eq $CandidateIdentity.Trim().ToLowerInvariant() -and $identityObserved -ne 'nt authority\system')
    $passed = ($queryPassed -and $reservedReadDenied -and $identityPassed)
    [ordered]@{ schemaVersion = 1; controlId = 'T1-R01'; passed = $passed; queryPassed = $queryPassed; reservedReadDenied = $reservedReadDenied; candidateIdentityDistinct = $identityPassed; candidateIdentity = $identityObserved } | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 -LiteralPath $ReportPath
    if (-not $passed) { exit 10 }
}
finally { $pipe.Dispose() }
exit 0
