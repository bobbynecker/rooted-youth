[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:Failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    $script:Failures.Add($Message)
  }
}

function Read-RepositoryFile {
  param([string]$RelativePath)

  return Get-Content -LiteralPath (Join-Path $script:RepositoryRoot $RelativePath) -Raw
}

$script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$config = (Read-RepositoryFile 'staticwebapp.config.json') | ConvertFrom-Json
$headers = $config.globalHeaders

$requiredHeaders = @{
  'Content-Security-Policy' = 'frame-ancestors ''none'''
  'Permissions-Policy' = 'camera=()'
  'Referrer-Policy' = 'strict-origin-when-cross-origin'
  'Strict-Transport-Security' = 'max-age=31536000'
  'X-Content-Type-Options' = 'nosniff'
  'X-Frame-Options' = 'DENY'
}

foreach ($headerName in $requiredHeaders.Keys) {
  $property = $headers.PSObject.Properties[$headerName]
  Assert-True ($null -ne $property) "Missing global security header: $headerName"
  if ($null -ne $property) {
    Assert-True ($property.Value -like "*$($requiredHeaders[$headerName])*") "Unexpected value for global header: $headerName"
  }
}

$csp = $headers.'Content-Security-Policy'
Assert-True ($csp -notmatch "'unsafe-inline'") 'CSP must not allow unsafe-inline.'
Assert-True ($csp -notmatch "'unsafe-eval'") 'CSP must not allow unsafe-eval.'
Assert-True ($csp -match "form-action https://formspree\.io") 'CSP must restrict form submissions to Formspree.'
Assert-True ($csp -match "object-src 'none'") 'CSP must block object embeds.'
Assert-True ($csp -match "frame-src 'none'") 'CSP must block framed content.'

$sensitiveRoutes = @(
  '/prayer-request',
  '/prayer-request.html',
  '/prayer-thank-you',
  '/prayer-thank-you.html'
)

foreach ($routePath in $sensitiveRoutes) {
  $route = $config.routes | Where-Object { $_.route -eq $routePath } | Select-Object -First 1
  Assert-True ($null -ne $route) "Missing sensitive route policy: $routePath"
  if ($null -ne $route) {
    Assert-True ($route.headers.'Cache-Control' -match 'no-store') "Sensitive route must be no-store: $routePath"
    Assert-True ($route.headers.'Referrer-Policy' -eq 'no-referrer') "Sensitive route must suppress referrers: $routePath"
    Assert-True ($route.headers.'X-Robots-Tag' -match 'noindex') "Sensitive route must be excluded from indexing: $routePath"
  }
}

$serviceWorker = Read-RepositoryFile 'service-worker.js'
$appShellMatch = [regex]::Match($serviceWorker, '(?s)const APP_SHELL = \[(?<body>.*?)\];')
Assert-True $appShellMatch.Success 'Could not inspect the service worker app shell.'
if ($appShellMatch.Success) {
  Assert-True ($appShellMatch.Groups['body'].Value -notmatch 'prayer-(request|thank-you)') 'Sensitive prayer pages must not be precached.'
}
foreach ($routePath in $sensitiveRoutes) {
  Assert-True ($serviceWorker.Contains("'$routePath'")) "Service worker does not recognize sensitive path: $routePath"
}
Assert-True ($serviceWorker -match "fetch\(event\.request, \{ cache: 'no-store' \}\)") 'Sensitive service-worker requests must use no-store.'

$htmlFiles = Get-ChildItem -LiteralPath $script:RepositoryRoot -Filter '*.html' -File
foreach ($htmlFile in $htmlFiles) {
  $content = Get-Content -LiteralPath $htmlFile.FullName -Raw

  foreach ($scriptTag in [regex]::Matches($content, '(?is)<script\b(?<attributes>[^>]*)>')) {
    Assert-True ($scriptTag.Groups['attributes'].Value -match '(?i)\bsrc\s*=') "Inline script conflicts with CSP: $($htmlFile.Name)"
  }

  Assert-True ($content -notmatch '(?i)\son[a-z][a-z0-9_-]*\s*=') "Inline event handler conflicts with CSP: $($htmlFile.Name)"
  Assert-True ($content -notmatch '(?i)\sstyle\s*=') "Inline style conflicts with CSP: $($htmlFile.Name)"
  Assert-True ($content -notmatch '(?i)http://') "Insecure HTTP resource found: $($htmlFile.Name)"

  foreach ($blankLink in [regex]::Matches($content, '(?is)<a\b[^>]*target=["'']_blank["''][^>]*>')) {
    Assert-True ($blankLink.Value -match '(?i)\brel=["''][^"'']*noopener') "target=_blank link is missing rel=noopener: $($htmlFile.Name)"
  }
}

$prayerPage = Read-RepositoryFile 'prayer-request.html'
$prayerThankYouPage = Read-RepositoryFile 'prayer-thank-you.html'
Assert-True ($prayerPage -match '<form[^>]+action="https://formspree\.io/') 'Prayer form must submit only over HTTPS to Formspree.'
Assert-True ($prayerPage -match '<meta name="robots" content="noindex, nofollow, noarchive"') 'Prayer request page must include a noindex fallback.'
Assert-True ($prayerThankYouPage -match '<meta name="robots" content="noindex, nofollow, noarchive"') 'Prayer thank-you page must include a noindex fallback.'
Assert-True ($prayerPage -match 'name="_gotcha"') 'Prayer form honeypot is missing.'
Assert-True ($prayerPage -match 'name="privacy_consent"[^>]+required') 'Prayer form privacy consent is missing or optional.'
Assert-True ($prayerPage -match 'name="message"[^>]+maxlength="4000"[^>]+required') 'Prayer message must be length-bounded and required.'
Assert-True ($prayerPage -match '<script src="prayer-form\.js"></script>') 'Prayer form behavior must remain in an external CSP-compatible script.'

$prayerScript = Read-RepositoryFile 'prayer-form.js'
Assert-True ($prayerScript -notmatch '(localStorage|sessionStorage|indexedDB)') 'Prayer form script must not persist request data in browser storage.'
Assert-True ($prayerScript -match "cache: 'no-store'") 'Prayer form submission must disable fetch caching.'
Assert-True ($prayerScript -match "credentials: 'omit'") 'Prayer form submission must omit credentials.'
Assert-True ($prayerScript -match "referrerPolicy: 'no-referrer'") 'Prayer form submission must suppress referrer data.'

$workflowRoot = Join-Path $script:RepositoryRoot '.github/workflows'
$workflowFiles = Get-ChildItem -LiteralPath $workflowRoot -File | Where-Object { $_.Extension -in @('.yml', '.yaml') }
foreach ($workflowFile in $workflowFiles) {
  $workflow = Get-Content -LiteralPath $workflowFile.FullName -Raw
  foreach ($actionUse in [regex]::Matches($workflow, '(?m)^\s*uses:\s*[^@\s]+@(?<ref>[^\s#]+)')) {
    Assert-True ($actionUse.Groups['ref'].Value -match '^[0-9a-f]{40}$') "GitHub Action is not pinned to a full commit SHA: $($workflowFile.Name)"
  }
}

$deploymentWorkflow = Read-RepositoryFile '.github/workflows/azure-static-web-apps.yml'
Assert-True ($deploymentWorkflow -notmatch 'repo_token:') 'Deployment must not pass an unnecessary GitHub token to the Azure action.'
Assert-True ($deploymentWorkflow -match '(?m)^permissions:\s*\r?\n\s+contents: read\s*$') 'Deployment workflow permissions must remain read-only.'
Assert-True ($deploymentWorkflow -match "if: github\.ref == 'refs/heads/main'") 'Production deployment must be restricted to the main branch.'

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if ($null -ne $nodeCommand) {
  foreach ($javascriptFile in Get-ChildItem -LiteralPath $script:RepositoryRoot -Filter '*.js' -File) {
    & $nodeCommand.Source --check $javascriptFile.FullName
    Assert-True ($LASTEXITCODE -eq 0) "JavaScript syntax check failed: $($javascriptFile.Name)"
  }
} else {
  Write-Host 'INFO: Node.js is unavailable; JavaScript parser checks will run in GitHub Actions.'
}

if ($script:Failures.Count -gt 0) {
  Write-Error ("Security checks failed:`n - " + ($script:Failures -join "`n - "))
}

Write-Host "Security checks passed ($($htmlFiles.Count) HTML files, $($workflowFiles.Count) workflows)."
