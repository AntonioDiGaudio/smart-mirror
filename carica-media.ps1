# Copia foto e video dalla cartella "media" del progetto al telefono (via USB).
# Uso: tasto destro > "Esegui con PowerShell", oppure da terminale: .\carica-media.ps1
# I file sul telefono che non sono più nella cartella del PC vengono rimossi.

$ErrorActionPreference = 'Stop'
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$pacchetto = 'com.antonio.vetro_bidirezionale'
$sulTelefono = "/sdcard/Android/data/$pacchetto/files/media"
$locale = Join-Path $PSScriptRoot 'media'

if (-not ((& $adb devices) -match "`tdevice$")) {
    Write-Host 'Telefono non trovato: collegalo via USB con il debug USB attivo.' -ForegroundColor Red
    exit 1
}

foreach ($tipo in 'foto', 'video') {
    $cartella = Join-Path $locale $tipo
    New-Item -ItemType Directory -Force $cartella | Out-Null
    & $adb shell mkdir -p "$sulTelefono/$tipo" | Out-Null

    $sulPc = @(Get-ChildItem -File $cartella | Select-Object -ExpandProperty Name)
    $presenti = @(& $adb shell ls -1 "$sulTelefono/$tipo" 2>$null | Where-Object { $_ })

    foreach ($nome in $presenti) {
        if ($sulPc -notcontains $nome) {
            Write-Host "Rimuovo $tipo/$nome"
            & $adb shell rm -f "'$sulTelefono/$tipo/$nome'" | Out-Null
        }
    }
    foreach ($nome in $sulPc) {
        if ($presenti -contains $nome) { continue }
        Write-Host "Copio $tipo/$nome"
        & $adb push (Join-Path $cartella $nome) "$sulTelefono/$tipo/$nome" | Out-Null
    }
}

# Modello vocale di Jarvis: si copia solo la prima volta (circa 90 MB).
$modello = "/sdcard/Android/data/$pacchetto/files/modello-vocale"
$giaCopiato = (& $adb shell "[ -f $modello/am/final.mdl ] && echo si") -eq 'si'
if (-not $giaCopiato) {
    Write-Host 'Copio il modello vocale di Jarvis (una volta sola, ci vuole un minuto)...'
    & $adb shell mkdir -p $modello | Out-Null
    & $adb push "$(Join-Path $PSScriptRoot 'modello-vocale')\." $modello | Out-Null
}

Write-Host 'Fatto. Riapri Foto o Video sullo specchio per vedere le novita''.' -ForegroundColor Green
