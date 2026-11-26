param([Parameter(Mandatory=$true, Position=0)][string] $InputPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Read-Text($Value, [string]$Name) {
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name must be a nonempty string"
    }
    return $Value.Trim()
}

function Read-Records($Value, [string]$Name) {
    if ($Value -isnot [array]) { throw "$Name must be a JSON array" }
    foreach ($entry in $Value) {
        if ($entry -isnot [System.Collections.IDictionary]) {
            throw "$Name must contain JSON objects"
        }
    }
    return ,$Value
}

function Read-Boolean($Value, [string]$Name) {
    if ($Value -isnot [bool]) { throw "$Name must be true or false" }
    return $Value
}

function Read-Whole($Value, [string]$Name, [int]$Minimum, [int]$Maximum) {
    if (($Value -isnot [long] -and $Value -isnot [int] -and $Value -isnot [double]) -or
        -not [double]::IsFinite($Value) -or [Math]::Truncate($Value) -ne $Value -or
        $Value -lt $Minimum -or $Value -gt $Maximum) {
        throw "$Name must be a whole number between $Minimum and $Maximum"
    }
    return [int]$Value
}

function Invoke-Analysis($data) {
    $allowMarked = Read-Boolean $data['allow_marked'] 'allow_marked'
    $sections = Read-Records $data['sections'] 'sections'
    $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $copyTotal = 0L
    $printTotal = 0L
    $report = @(foreach ($section in $sections) {
        $name = Read-Text $section['part'] 'part'
        if (-not $names.Add($name)) { throw "Duplicate part $name" }
        $players = Read-Whole $section['players'] "players for $name" 0 10000
        $share = Read-Whole $section['players_per_copy'] "players_per_copy for $name" 1 10000
        $reserve = Read-Whole $section['spares'] "spares for $name" 0 10000
        $clean = Read-Whole $section['clean_copies'] "clean_copies for $name" 0 10000
        $marked = Read-Whole $section['marked_copies'] "marked_copies for $name" 0 10000
        $required = [int][Math]::Ceiling($players / $share) + $reserve
        $available = if ($allowMarked) { $clean + $marked } else { $clean }
        $missing = [Math]::Max(0, $required - $available)
        $copyTotal += $required
        $printTotal += $missing
        [ordered]@{
            part = $name
            copies_needed = $required
            copies_available = $available
            copies_to_print = $missing
        }
    })
    return [ordered]@{ copies_needed = $copyTotal; copies_to_print = $printTotal; parts = $report }
}

try {
    $payload = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json -AsHashtable
    if ($payload -isnot [System.Collections.IDictionary]) { throw 'Input must be a JSON object' }
    Invoke-Analysis $payload | ConvertTo-Json -Depth 30 -Compress
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 2
}
