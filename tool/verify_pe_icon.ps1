# Extrae los recursos RT_ICON (tipo 3) de un PE y, por cada uno, imprime
# longitud + suma de bytes + suma ponderada. Un .ico de disco que provenga del
# mismo origen (hs_icon.png) produce las mismas cifras para alguna entrada.
# Comparar con: node tool/verify_pe_icon.js <ico>  (imprime lo mismo por entrada).
param(
  [string]$Exe = "build\windows\x64\runner\Release\HardstreetAdmin.exe"
)

$fs = [System.IO.File]::OpenRead((Resolve-Path $Exe).Path)
$b  = New-Object System.IO.BinaryReader($fs)

$fs.Seek(0x3c, 'Begin') | Out-Null
$peOff = $b.ReadInt32()
$fs.Seek($peOff + 6, 'Begin') | Out-Null
$numSec = $b.ReadUInt16(); $null = $b.ReadUInt16(); $optSize = $b.ReadUInt16()
$fs.Seek($peOff + 24, 'Begin') | Out-Null
$magic = $b.ReadUInt16()
$ddOff = if ($magic -eq 0x20b) { $peOff + 24 + 112 } else { $peOff + 24 + 96 }
$fs.Seek($ddOff + 16, 'Begin') | Out-Null
$rsrcRva = $b.ReadUInt32(); $null = $b.ReadUInt32()

$secOff = $peOff + 24 + $optSize
$secs = @()
for ($i = 0; $i -lt $numSec; $i++) {
  $fs.Seek($secOff + $i * 40, 'Begin') | Out-Null
  $null = $b.ReadBytes(8)
  $vsize = $b.ReadUInt32(); $vaddr = $b.ReadUInt32()
  $rawSize = $b.ReadUInt32(); $rawPtr = $b.ReadUInt32()
  $secs += ,@{ va = $vaddr; vs = $vsize; rp = $rawPtr; rs = $rawSize }
}

function Convert-RvaToOffset([int]$rva) {
  foreach ($s in $secs) {
    $span = [Math]::Max($s.vs, $s.rs)
    if ($rva -ge $s.va -and $rva -lt ($s.va + $span)) { return $s.rp + ($rva - $s.va) }
  }
  return -1
}

function Read-DirCount([int]$off) {
  $fs.Seek($off + 4, 'Begin') | Out-Null
  $ids = $b.ReadUInt32()
  return ($ids -band 0xFFFF)
}
function Read-DirSlot([int]$off, [int]$idx) {
  $fs.Seek($off + 16 + $idx * 8, 'Begin') | Out-Null
  $name = $b.ReadUInt32(); $ptr = $b.ReadUInt32()
  return @{ id = ($name -band 0xFFFF); isDir = ($ptr -shr 31); off = ($ptr -band 0x7FFFFFFF) }
}

$rsrcOff = Convert-RvaToOffset $rsrcRva
$rootCount = Read-DirCount $rsrcOff
Write-Host "sections=$numSec rsrcRva=$rsrcRva rsrcOff=$rsrcOff rootEntries=$rootCount"

$results = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $rootCount; $i++) {
  $type = Read-DirSlot $rsrcOff $i
  if ($type.id -ne 3) { continue }
  $typeOff = $rsrcOff + $type.off
  $imgCount = Read-DirCount $typeOff
  for ($j = 0; $j -lt $imgCount; $j++) {
    $img = Read-DirSlot $typeOff $j
    $dataOff = Convert-RvaToOffset ($rsrcOff + $img.off)
    $fs.Seek($dataOff, 'Begin') | Out-Null
    $dataRva = $b.ReadUInt32(); $size = $b.ReadUInt32()
    $fileOff = Convert-RvaToOffset $dataRva
    $fs.Seek($fileOff, 'Begin') | Out-Null
    $bytes = $b.ReadBytes([int]$size)
    $sum = [uint64]0; $wsum = [uint64]0
    for ($k = 0; $k -lt $bytes.Length; $k++) {
      $sum += $bytes[$k]
      $wsum += [uint64]$bytes[$k] * [uint64]($k % 251)
    }
    [void]$results.Add(@{ size = $bytes.Length; sum = $sum; wsum = $wsum })
  }
}
$b.Close(); $fs.Close()

Write-Host "RT_ICON resources: $($results.Count)"
foreach ($r in $results) {
  Write-Host ("  RT_ICON size={0} sum={1} wsum={2}" -f $r.size, $r.sum, $r.wsum)
}
Write-Host "(comparar con la salida de: node tool/verify_pe_icon.js <ico>)"
