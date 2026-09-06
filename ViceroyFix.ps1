param(
    [string]$TargetPath
)

$ErrorActionPreference = "Stop"

$OriginalHash = "9b69230360a2b7a8fd3b4cb8cee06e81ddebcc4cd7ea05f4008c0d9fb39433f2"
$AudioHash    = "35dd99256a689d39a14e6a8d99ca145daa25dbea9591b12e7007a58fc90e3c5d"
$BothFixesHash = "37a862f889ffcde626beaf2a28af72e4fa623cc430b5f90ff794794806d59e3e"
# Known non-public development state. Supported only so it can be removed.
$LegacyShortcutHash = "cd38ab63d21e06426f5b96b7b3d782d2d6ca91da37a1aa9c1bfb44f2c304c09c"

# Fixed offsets for the supported build, inside the uncompressed
# "the viceroy__main__.pyc" payload.
$AudioOffset = 156863
$CodeLengthOffset = 861384
$AchievementBlockOffset = 869068
$TrampolineInsertOffset = 933191

[byte[]]$AudioOriginal = @(124,59,0,106,82,0,131,0,0,1)
[byte[]]$AudioPatched  = @(9,9,9,9,9,9,9,9,9,9)

# Shipped broken condition block:
# gameData['territory']['weightOfCulture'].values() == 1000
# followed by the game's existing Steam unlock call.
[byte[]]$AchievementOriginal = @(
    124,0,0,100,11,0,25,100,143,0,25,106,16,0,131,0,0,
    100,144,0,107,2,0,114,42,30,
    116,17,0,106,18,0,100,145,0,131,1,0,1,110,0,0
)

# Redirect to appended corrected condition logic, preserving the original
# bytecode footprint so existing offsets remain stable.
[byte[]]$AchievementRedirect = @(
    110,120,250,
    9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
    9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9
)

# Appended Python 3.2 bytecode equivalent to:
# if sum(gameData['territory']['weightOfCulture'].values()) == 1000:
#     steam.unlock_achievement('MILLENNIAL_REIGN')
# then jump back to the original next instruction.
[byte[]]$AchievementTrampoline = @(
    116,26,0,124,0,0,100,11,0,25,100,143,0,25,106,16,0,131,0,0,
    131,1,0,100,144,0,107,2,0,144,1,0,114,174,24,
    116,17,0,106,18,0,100,145,0,131,1,0,1,113,42,30,113,42,30
)

[byte[]]$OldCodeLength = @(123,24,1,0)   # 71803
[byte[]]$NewCodeLength = @(177,24,1,0)   # 71857

# The temporary pre-release shortcut changed only these 3 bytes in the
# original achievement block. We recognize it solely to restore real logic.
$LegacyShortcutOffset = 869091
[byte[]]$LegacyShortcutBytes = @(1,9,9)
[byte[]]$OriginalJumpBytes   = @(114,42,30)

function Get-ByteHash([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    }
    finally {
        $sha.Dispose()
    }
}

function Test-BytesAt([byte[]]$Bytes, [int]$Offset, [byte[]]$Pattern) {
    if ($Offset -lt 0 -or ($Offset + $Pattern.Length) -gt $Bytes.Length) {
        return $false
    }
    for ($i = 0; $i -lt $Pattern.Length; $i++) {
        if ($Bytes[$Offset + $i] -ne $Pattern[$i]) {
            return $false
        }
    }
    return $true
}

function Set-BytesAt([byte[]]$Bytes, [int]$Offset, [byte[]]$Expected, [byte[]]$Replacement) {
    if ($Expected.Length -ne $Replacement.Length) {
        throw "Internal patch error: replacement length differs."
    }
    if (-not (Test-BytesAt $Bytes $Offset $Expected)) {
        throw "Expected bytes were not found at offset $Offset. Refusing to patch."
    }
    for ($i = 0; $i -lt $Replacement.Length; $i++) {
        $Bytes[$Offset + $i] = $Replacement[$i]
    }
}

function Insert-Bytes([byte[]]$Bytes, [int]$Offset, [byte[]]$Addition) {
    if ($Offset -lt 0 -or $Offset -gt $Bytes.Length) {
        throw "Internal patch error: invalid insertion offset."
    }
    [byte[]]$result = New-Object byte[] ($Bytes.Length + $Addition.Length)
    [Array]::Copy($Bytes, 0, $result, 0, $Offset)
    [Array]::Copy($Addition, 0, $result, $Offset, $Addition.Length)
    [Array]::Copy(
        $Bytes, $Offset,
        $result, $Offset + $Addition.Length,
        $Bytes.Length - $Offset
    )
    return $result
}

function Remove-Bytes([byte[]]$Bytes, [int]$Offset, [int]$Count) {
    if ($Offset -lt 0 -or $Count -lt 0 -or ($Offset + $Count) -gt $Bytes.Length) {
        throw "Internal patch error: invalid removal range."
    }
    [byte[]]$result = New-Object byte[] ($Bytes.Length - $Count)
    [Array]::Copy($Bytes, 0, $result, 0, $Offset)
    [Array]::Copy(
        $Bytes, $Offset + $Count,
        $result, $Offset,
        $Bytes.Length - ($Offset + $Count)
    )
    return $result
}

function Resolve-LibraryZip([string]$InputPath) {
    if ($InputPath) {
        $p = $InputPath.Trim('"')
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            if ([IO.Path]::GetFileName($p) -ieq "library.zip") {
                return (Resolve-Path -LiteralPath $p).Path
            }
        }
        if (Test-Path -LiteralPath $p -PathType Container) {
            $candidate = Join-Path $p "library.zip"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }

    $defaults = @(
        "${env:ProgramFiles(x86)}\Steam\steamapps\common\The Viceroy\library.zip",
        "$env:ProgramFiles\Steam\steamapps\common\The Viceroy\library.zip"
    )

    foreach ($candidate in $defaults) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    Write-Host ""
    Write-Host "The default Steam installation was not found."
    $entered = Read-Host "Paste the full path to The Viceroy folder OR library.zip"
    return Resolve-LibraryZip $entered
}

function Read-MainPyc([string]$LibraryZip) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $zip = [System.IO.Compression.ZipFile]::OpenRead($LibraryZip)
    try {
        $entry = $zip.Entries | Where-Object {
            $_.FullName -ieq "the viceroy__main__.pyc" -or
            $_.FullName.EndsWith("/the viceroy__main__.pyc", [StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1

        if (-not $entry) {
            throw "Could not find 'the viceroy__main__.pyc' inside library.zip."
        }

        $stream = $entry.Open()
        try {
            $ms = New-Object System.IO.MemoryStream
            try {
                $stream.CopyTo($ms)
                return @{
                    Bytes = $ms.ToArray()
                    EntryName = $entry.FullName
                }
            }
            finally { $ms.Dispose() }
        }
        finally { $stream.Dispose() }
    }
    finally { $zip.Dispose() }
}

function Write-MainPyc([string]$LibraryZip, [string]$EntryName, [byte[]]$Bytes) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $zip = [System.IO.Compression.ZipFile]::Open(
        $LibraryZip,
        [System.IO.Compression.ZipArchiveMode]::Update
    )
    try {
        $entry = $zip.GetEntry($EntryName)
        if (-not $entry) {
            $entry = $zip.Entries | Where-Object {
                $_.FullName -ieq $EntryName
            } | Select-Object -First 1
        }
        if (-not $entry) {
            throw "Could not reopen the main game entry for writing."
        }

        $name = $entry.FullName
        $entry.Delete()

        $newEntry = $zip.CreateEntry(
            $name,
            [System.IO.Compression.CompressionLevel]::Optimal
        )
        $out = $newEntry.Open()
        try {
            $out.Write($Bytes, 0, $Bytes.Length)
        }
        finally { $out.Dispose() }
    }
    finally { $zip.Dispose() }
}

function Ensure-Backup([string]$LibraryZip) {
    $backup = "$LibraryZip.viceroyfix-original"
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $LibraryZip -Destination $backup
        Write-Host "Created backup: $backup"
    }
    else {
        Write-Host "Backup already exists; leaving it untouched."
    }
    return $backup
}

function Apply-AudioFix([byte[]]$Bytes) {
    if (Test-BytesAt $Bytes $AudioOffset $AudioOriginal) {
        Set-BytesAt $Bytes $AudioOffset $AudioOriginal $AudioPatched
    }
    elseif (-not (Test-BytesAt $Bytes $AudioOffset $AudioPatched)) {
        throw "Audio patch site is not in a recognized state."
    }
    return $Bytes
}

function Remove-LegacyShortcut([byte[]]$Bytes) {
    if (Test-BytesAt $Bytes $LegacyShortcutOffset $LegacyShortcutBytes) {
        Set-BytesAt $Bytes $LegacyShortcutOffset $LegacyShortcutBytes $OriginalJumpBytes
    }
    return $Bytes
}

function Apply-MillennialFix([byte[]]$Bytes) {
    if (-not (Test-BytesAt $Bytes $CodeLengthOffset $OldCodeLength)) {
        throw "Millennial Reign code-object length is not in the expected original state."
    }
    if (-not (Test-BytesAt $Bytes $AchievementBlockOffset $AchievementOriginal)) {
        throw "Millennial Reign patch site is not in the expected original state."
    }

    Set-BytesAt $Bytes $CodeLengthOffset $OldCodeLength $NewCodeLength
    Set-BytesAt $Bytes $AchievementBlockOffset $AchievementOriginal $AchievementRedirect
    return Insert-Bytes $Bytes $TrampolineInsertOffset $AchievementTrampoline
}

function Remove-MillennialFix([byte[]]$Bytes) {
    if (-not (Test-BytesAt $Bytes $CodeLengthOffset $NewCodeLength)) {
        throw "Millennial Reign code-object length is not in the expected patched state."
    }
    if (-not (Test-BytesAt $Bytes $AchievementBlockOffset $AchievementRedirect)) {
        throw "Millennial Reign redirect is not in the expected patched state."
    }
    if (-not (Test-BytesAt $Bytes $TrampolineInsertOffset $AchievementTrampoline)) {
        throw "Millennial Reign trampoline is not in the expected patched state."
    }

    $Bytes = Remove-Bytes $Bytes $TrampolineInsertOffset $AchievementTrampoline.Length
    Set-BytesAt $Bytes $CodeLengthOffset $NewCodeLength $OldCodeLength
    Set-BytesAt $Bytes $AchievementBlockOffset $AchievementRedirect $AchievementOriginal
    return $Bytes
}

function State-Name([string]$Hash) {
    switch ($Hash) {
        $OriginalHash { return "Original supported build" }
        $AudioHash    { return "Audio fix only" }
        $BothFixesHash { return "Both fixes installed" }
        $LegacyShortcutHash { return "Known pre-release temporary shortcut state" }
        default       { return "Unknown / unsupported build" }
    }
}

$LibraryZip = Resolve-LibraryZip $TargetPath
if (-not $LibraryZip) {
    throw "No library.zip selected."
}

Write-Host ""
Write-Host "The Viceroy Community Fix 1.0.0"
Write-Host "Target: $LibraryZip"
Write-Host ""

$loaded = Read-MainPyc $LibraryZip
[byte[]]$bytes = $loaded.Bytes
$entryName = $loaded.EntryName
$currentHash = Get-ByteHash $bytes

Write-Host "Current state: $(State-Name $currentHash)"
Write-Host "SHA-256: $currentHash"
Write-Host ""
Write-Host "1 - Apply BOTH bug fixes (recommended)"
Write-Host "2 - Apply audio-device crash fix only"
Write-Host "3 - Restore original library.zip backup"
Write-Host "4 - Exit"
Write-Host ""

$choice = Read-Host "Choose 1-4"

if ($choice -eq "4") {
    exit 0
}

if ($choice -eq "3") {
    $backup = "$LibraryZip.viceroyfix-original"
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
        throw "No backup found at $backup"
    }
    Copy-Item -LiteralPath $backup -Destination $LibraryZip -Force
    Write-Host ""
    Write-Host "Original library.zip restored."
    exit 0
}

if ($currentHash -notin @(
    $OriginalHash,
    $AudioHash,
    $BothFixesHash,
    $LegacyShortcutHash
)) {
    throw "This build is not recognized. Nothing was changed."
}

Ensure-Backup $LibraryZip | Out-Null

if ($choice -eq "1") {
    if ($currentHash -eq $BothFixesHash) {
        Write-Host "Both fixes are already installed."
        exit 0
    }

    # If the non-public development shortcut was ever tested, remove it first.
    if ($currentHash -eq $LegacyShortcutHash) {
        $bytes = Remove-LegacyShortcut $bytes
        $afterLegacyRemoval = Get-ByteHash $bytes
        if ($afterLegacyRemoval -ne $AudioHash) {
            throw "Could not cleanly remove the pre-release shortcut state."
        }
    }

    $bytes = Apply-AudioFix $bytes
    $bytes = Apply-MillennialFix $bytes

    $newHash = Get-ByteHash $bytes
    if ($newHash -ne $BothFixesHash) {
        throw "Patch output did not match the expected final hash. Nothing written."
    }
}
elseif ($choice -eq "2") {
    if ($currentHash -eq $AudioHash) {
        Write-Host "Audio fix is already installed."
        exit 0
    }

    if ($currentHash -eq $LegacyShortcutHash) {
        $bytes = Remove-LegacyShortcut $bytes
        $newHash = Get-ByteHash $bytes
        if ($newHash -ne $AudioHash) {
            throw "Could not cleanly remove the pre-release shortcut state."
        }
    }
    elseif ($currentHash -eq $BothFixesHash) {
        $bytes = Remove-MillennialFix $bytes
        $newHash = Get-ByteHash $bytes
        if ($newHash -ne $AudioHash) {
            throw "Could not cleanly remove the Millennial Reign fix."
        }
    }
    elseif ($currentHash -eq $OriginalHash) {
        $bytes = Apply-AudioFix $bytes
        $newHash = Get-ByteHash $bytes
        if ($newHash -ne $AudioHash) {
            throw "Audio patch output did not match the expected hash."
        }
    }
}
else {
    throw "Invalid choice."
}

Write-MainPyc $LibraryZip $entryName $bytes

$verify = Read-MainPyc $LibraryZip
$verifyHash = Get-ByteHash $verify.Bytes

if ($choice -eq "1" -and $verifyHash -ne $BothFixesHash) {
    throw "Verification failed after writing library.zip."
}
if ($choice -eq "2" -and $verifyHash -ne $AudioHash) {
    throw "Verification failed after writing library.zip."
}

Write-Host ""
Write-Host "Success."
Write-Host "New state: $(State-Name $verifyHash)"
Write-Host "SHA-256: $verifyHash"
Write-Host ""
if ($choice -eq "1") {
    Write-Host "Millennial Reign now checks the actual Territory turn total and"
    Write-Host "unlocks only when that total reaches exactly 1,000."
}
