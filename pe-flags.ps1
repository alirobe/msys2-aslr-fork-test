# Inspect or set PE DllCharacteristics (dynamicbase 0x40, high-entropy-va 0x20) and report relocation info.
param([Parameter(Mandatory)][string[]]$Paths, [string]$SetDynamicBaseCopyTo)
foreach ($p in $Paths) {
    $b = [System.IO.File]::ReadAllBytes($p)
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    $machine = [BitConverter]::ToUInt16($b, $pe + 4)
    $nsec = [BitConverter]::ToUInt16($b, $pe + 6)
    $optSize = [BitConverter]::ToUInt16($b, $pe + 20)
    $coffChar = [BitConverter]::ToUInt16($b, $pe + 22)
    $opt = $pe + 24
    $magic = [BitConverter]::ToUInt16($b, $opt)
    $dllChar = [BitConverter]::ToUInt16($b, $opt + 70)
    $imageBase = if ($magic -eq 0x20B) { [BitConverter]::ToUInt64($b, $opt + 24) } else { [BitConverter]::ToUInt32($b, $opt + 28) }
    $secTab = $opt + $optSize
    $hasReloc = $false
    for ($i = 0; $i -lt $nsec; $i++) { $name = [System.Text.Encoding]::ASCII.GetString($b, $secTab + $i*40, 8).TrimEnd([char]0); if ($name -eq '.reloc') { $hasReloc = $true } }
    "{0}: magic=0x{1:X} base=0x{2:X} DllChar=0x{3:X4} dynamicbase={4} highentropy={5} relocs_stripped={6} .reloc={7}" -f (Split-Path $p -Leaf), $magic, $imageBase, $dllChar, (($dllChar -band 0x40) -ne 0), (($dllChar -band 0x20) -ne 0), (($coffChar -band 1) -ne 0), $hasReloc
    if ($SetDynamicBaseCopyTo) {
        $new = $dllChar -bor 0x40
        [Array]::Copy([BitConverter]::GetBytes([uint16]$new), 0, $b, $opt + 70, 2)
        [System.IO.File]::WriteAllBytes($SetDynamicBaseCopyTo, $b)
        "  -> wrote $SetDynamicBaseCopyTo with DllChar=0x{0:X4}" -f $new
    }
}
