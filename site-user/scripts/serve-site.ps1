[CmdletBinding()]
param(
    [string]$SitePath = (Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'site'),
    [int]$Port = 4173
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $SitePath).Path
$server = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$server.Start()
Write-Host "Serving $root at http://localhost:$Port/"

$contentTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
}

while ($true) {
    $client = $server.AcceptTcpClient()
    try {
        $stream = $client.GetStream()
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
        $requestLine = $reader.ReadLine()
        while ($reader.ReadLine()) { }

        $requestPath = '/'
        if ($requestLine -match '^[A-Z]+\s+([^\s]+)\s+HTTP/') {
            $requestPath = $Matches[1].Split('?')[0]
        }

        $relativePath = [Uri]::UnescapeDataString($requestPath.TrimStart('/'))
        if ([string]::IsNullOrWhiteSpace($relativePath)) { $relativePath = 'index.html' }

        $candidate = Join-Path $root $relativePath
        if ((Test-Path -LiteralPath $candidate -PathType Container)) {
            $candidate = Join-Path $candidate 'index.html'
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $candidate = Join-Path $root 'index.html'
        }

        $file = Get-Item -LiteralPath $candidate
        if (-not $file.FullName.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            $body = [System.Text.Encoding]::UTF8.GetBytes('Forbidden')
            $header = "HTTP/1.1 403 Forbidden`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
            $stream.Write([System.Text.Encoding]::ASCII.GetBytes($header))
            $stream.Write($body)
            continue
        }

        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $extension = $file.Extension.ToLowerInvariant()
        $contentType = $contentTypes[$extension] ?? 'application/octet-stream'
        $header = "HTTP/1.1 200 OK`r`nContent-Type: $contentType`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
        $stream.Write([System.Text.Encoding]::ASCII.GetBytes($header))
        $stream.Write($bytes)
    }
    catch {
        try {
            $body = [System.Text.Encoding]::UTF8.GetBytes('Server error')
            $header = "HTTP/1.1 500 Internal Server Error`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
            $client.GetStream().Write([System.Text.Encoding]::ASCII.GetBytes($header))
            $client.GetStream().Write($body)
        }
        catch { }
    }
    finally {
        $client.Close()
    }
}
