# Instala o pacote de agentes SigmaCode (pastas .claude e docs\phc) num repositório de trabalho.
# Uso:  powershell -NoProfile -ExecutionPolicy RemoteSigned -File instalar.ps1 -Destino C:\_SigmaRepos\sServices
# Por defeito não sobrescreve ficheiros que já existam no destino. Com -Atualizar sobrescreve os do pacote.
# Não faz commit nem push e não mexe em mais nada do repositório além do .gitignore.
param(
    [Parameter(Mandatory = $true)][string]$Destino,
    [switch]$Atualizar
)

$ErrorActionPreference = 'Stop'
$origem = $PSScriptRoot
$destino = (Resolve-Path $Destino).Path

# O destino tem de ser um repositório git (o agente sc-dev usa worktrees).
if (-not (Test-Path (Join-Path $destino '.git'))) { throw "O destino não é um repositório git: $destino" }

# Só estas pastas do pacote vão para o repositório. O resto (README, projeto) fica no pacote.
$pastas = @('.claude', 'docs\phc')
$script:copiados = 0
$script:ignorados = 0
foreach ($p in $pastas) {
    $base = Join-Path $origem $p
    if (-not (Test-Path $base)) { throw "Pacote incompleto, falta a pasta: $p" }
    Get-ChildItem -Path $base -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($origem.Length).TrimStart('\')
        $alvo = Join-Path $destino $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $alvo) | Out-Null
        if ((Test-Path $alvo) -and -not $Atualizar) {
            $script:ignorados++
            Write-Host "ignorado (já existe): $rel"
        }
        else {
            Copy-Item $_.FullName $alvo -Force
            $script:copiados++
        }
    }
}

# Acrescenta ao .gitignore as linhas que faltam (nunca remove nada).
$gitignore = Join-Path $destino '.gitignore'
$linhas = @('Claude outputs/', '.claude/settings.local.json', '.claude/worktrees/')
$atuais = @()
if (Test-Path $gitignore) { $atuais = Get-Content $gitignore }
foreach ($l in $linhas) {
    if ($atuais -notcontains $l) { Add-Content -Path $gitignore -Value $l }
}

Write-Host "Instalação concluída em $destino. Copiados: $($script:copiados). Ignorados (já existiam): $($script:ignorados)."
