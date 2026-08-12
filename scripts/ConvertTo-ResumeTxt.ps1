<#
.SYNOPSIS
  Converts README.md into an ATS-friendly resume.txt (plain text).

.DESCRIPTION
  Zero-dependency PowerShell 7+ generator. Strips Markdown to plain text and
  reshapes headings into ALL-CAPS ATS section labels so applicant-tracking
  systems can parse the resume reliably.

  Run:    pwsh ./scripts/ConvertTo-ResumeTxt.ps1
  Output: ./resume.txt (next to README.md)

.PARAMETER Source
  Source markdown file. Defaults to README.md in the current directory.

.PARAMETER Output
  Destination plain-text file. Defaults to resume.txt.

.EXAMPLE
  pwsh ./scripts/ConvertTo-ResumeTxt.ps1
  pwsh ./scripts/ConvertTo-ResumeTxt.ps1 -Source README.md -Output resume.txt
#>
[CmdletBinding()]
param(
    [string]$Source = 'README.md',
    [string]$Output = 'resume.txt'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source)) {
    throw "Source not found: $Source"
}

$text = Get-Content -LiteralPath $Source -Raw

# 1. Drop images: ![alt](path) on its own line
$text = $text -replace '(?m)^[ \t]*!\[[^\]]*\]\([^)]*\)[ \t]*\r?\n?', ''

# 2. Strip blockquote markers ("> ")
$text = $text -replace '(?m)^[ \t]*>\s?', ''

# 3. Headings (tolerant to leading whitespace and an optional bullet prefix
#    like "* #### Task performed:"):
#    `## Foo`   -> `FOO`        (top-level ATS section, ALL CAPS)
#    `### Foo` / `#### Foo` -> `Foo` (subheadings, title-case, marker stripped)
$upperHeading = {
    param($match)
    return $match.Groups[1].Value.ToUpper()
}
$text = [regex]::Replace($text, '(?m)^[ \t]*(?:[-*][ \t]+)?#{2}\s+([^\r\n]+)$', $upperHeading)
$text = $text -replace '(?m)^[ \t]*(?:[-*][ \t]+)?#{3,4}\s+([^\r\n]+)$', '$1'
$text = $text -replace '(?m)^[ \t]*(?:[-*][ \t]+)?#\s+([^\r\n]+)$', '$1'

# 4. Inline formatting
$text = $text -replace '\*\*([^*]+)\*\*', '$1'                 # bold
$text = $text -replace '(?<!\*)\*([^*]+)\*(?!\*)', '$1'         # italic (not bold)
$text = $text -replace '~~([^~]+)~~', '$1'                     # strikethrough
$text = $text -replace '`([^`]+)`', '$1'                       # inline code
$text = $text -replace '\[([^\]]+)\]\(([^)]+)\)', '$1 ($2)'     # links -> text (url)

# 5. Horizontal rules -> separator line
$text = $text -replace '(?m)^---+\s*$', '------------------------------------------------------------'

# 6. Normalize list bullets: keep " - " style, collapse extra indent
$text = $text -replace '(?m)^[ \t]*[-*][ \t]+', ' - '

# 6a. Glue comma-continuations: a bullet item ending with "," whose next line
#     is not a new bullet/heading gets the next line appended. ATS reads the
#     stack as one line instead of fragmenting it.
$lines = $text -split "`r?`n"
$merged = [System.Collections.Generic.List[string]]::new()
foreach ($line in $lines) {
    if ($merged.Count -eq 0) { $merged.Add($line); continue }
    $prev = $merged[$merged.Count - 1]
    $prevEndsWithComma = $prev -match ',\s*$'
    $currIsNewBullet = $line -match '^[ \t]*[-*][ \t]+'
    $currIsHeading = $line -match '^[ \t]*(?:[-*][ \t]+)?#{1,6}\s'
    if ($prevEndsWithComma -and -not $currIsNewBullet -and -not $currIsHeading -and $line.Trim() -ne '') {
        $merged[$merged.Count - 1] = $prev.TrimEnd() + ' ' + $line.Trim()
    } else {
        $merged.Add($line)
    }
}
$text = $merged -join "`n"

# 7. Trim trailing spaces per line
$text = $text -replace '(?m)[ \t]+$', ''

# 8. Collapse 3+ blank lines to 2
$text = $text -replace '(\r?\n){3,}', "$([Environment]::NewLine * 2)"

# 9. Ensure CRLF on Windows / LF elsewhere (use platform default)
$lf = "`n"
$crlf = "`r`n"
if (-not $IsWindows) { $text = $text -replace "`r`n", $lf }

$text = $text.Trim()

Set-Content -LiteralPath $Output -Value $text -NoNewline -Encoding utf8

$lineCount = ($text -split "`r?`n").Count
Write-Host "Wrote $Output ($lineCount lines, $($text.Length) chars)"
