# Scarica il modello vocale italiano di Vosk (circa 48 MB, licenza Apache 2.0)
# nella cartella "modello-vocale". Poi carica-media.ps1 lo copia sul telefono.
# Uso: .\scarica-modello.ps1

$ErrorActionPreference = 'Stop'
$destinazione = Join-Path $PSScriptRoot 'modello-vocale'
if (Test-Path (Join-Path $destinazione 'am\final.mdl')) {
    Write-Host 'Il modello vocale c''e'' gia''.' -ForegroundColor Green
    exit 0
}

$zip = Join-Path $env:TEMP 'vosk-model-small-it-0.22.zip'
$temp = Join-Path $env:TEMP 'vosk-model-small-it-0.22-estratto'
Write-Host 'Scarico il modello vocale italiano (circa 48 MB)...'
Invoke-WebRequest 'https://alphacephei.com/vosk/models/vosk-model-small-it-0.22.zip' -OutFile $zip
Expand-Archive $zip -DestinationPath $temp -Force
New-Item -ItemType Directory -Force $destinazione | Out-Null
Copy-Item (Join-Path $temp 'vosk-model-small-it-0.22\*') $destinazione -Recurse -Force
Remove-Item $zip, $temp -Recurse -Force

# Regolazioni per lo specchio: aspetta piu' silenzio prima di chiudere la frase
# (cosi' non taglia chi fa una pausa) e cerca un po' piu' a fondo (capisce meglio).
$conf = Join-Path $destinazione 'conf\model.conf'
(Get-Content $conf) `
    -replace '^--max-active=.*', '--max-active=7000' `
    -replace '^--beam=.*', '--beam=13.0' `
    -replace 'rule2.min-trailing-silence=.*', 'rule2.min-trailing-silence=1.0' `
    -replace 'rule3.min-trailing-silence=.*', 'rule3.min-trailing-silence=1.2' `
    -replace 'rule4.min-trailing-silence=.*', 'rule4.min-trailing-silence=1.5' |
    Set-Content $conf -Encoding ascii
Write-Host 'Fatto. Ora collega il telefono e lancia carica-media.ps1' -ForegroundColor Green
