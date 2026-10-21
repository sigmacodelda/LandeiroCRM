<#
.SYNOPSIS
    Corre os testes SQL (01 a 07) na LAND2_DEMO e mostra o resumo. Cada teste faz ROLLBACK no fim.

.DESCRIPTION
    - RECUSA correr em qualquer base que não seja a LAND2_DEMO.
    - A password NÃO é pedida como parâmetro: vem da variável de ambiente CRMSYNC_SQL_PASSWORD
      (ou, se não existir, é pedida de forma segura). Alternativa: autenticação integrada do Windows (-Integrada).
    - Requer o sqlcmd instalado (ODBC Driver / SQL Server command line utilities).

.EXAMPLE
    $env:CRMSYNC_SQL_PASSWORD = '<password>'; .\executar_testes.ps1 -Servidor 'tcp:192.168.10.79\ENT' -Utilizador sa
    .\executar_testes.ps1 -Servidor 'tcp:SERVIDOR\INSTANCIA' -Integrada
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Servidor,
    [string]$BaseDados = 'LAND2_DEMO',
    [string]$Utilizador,
    [switch]$Integrada
)

$ErrorActionPreference = 'Stop'
if ($BaseDados -ne 'LAND2_DEMO') { throw "Os testes só podem correr na LAND2_DEMO (pedido: $BaseDados)." }

$autenticacao = @()
if ($Integrada) { $autenticacao = @('-E') }
else {
    if (-not $Utilizador) { throw 'Indicar -Utilizador ou usar -Integrada.' }
    $palavra = $env:CRMSYNC_SQL_PASSWORD
    if (-not $palavra) {
        $segura = Read-Host "Password de $Utilizador" -AsSecureString
        $palavra = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($segura))
    }
    $autenticacao = @('-U', $Utilizador, '-P', $palavra)
}

# (-Filter não aceita intervalos [1-6]: filtra-se pelo nome)
$testes = @(Get-ChildItem -Path $PSScriptRoot -Filter '*_teste_*.sql' | Where-Object { $_.Name -match '^0[1-7]_' } | Sort-Object Name)
# Nunca passar "em vazio": sem testes encontrados, isto é um erro
if ($testes.Count -ne 7) { throw "Esperava 7 ficheiros de teste (01 a 07) e encontrei $($testes.Count) em $PSScriptRoot." }
$falhas = 0
foreach ($teste in $testes) {
    Write-Host "=== $($teste.Name)" -ForegroundColor Cyan
    $saida = & sqlcmd -S $Servidor -d $BaseDados -C -f 65001 -b -W @autenticacao -i $teste.FullName 2>&1
    $resumo = $saida | Select-String -Pattern '^\s*\d+\s+\d+\s+\d+\s*$' | Select-Object -Last 1
    $falhou = $saida | Select-String -Pattern 'FALHOU'
    if ($LASTEXITCODE -ne 0 -or $falhou) {
        $falhas++
        Write-Host 'FALHOU' -ForegroundColor Red
        $saida | Select-String -Pattern 'FALHOU|Msg ' | ForEach-Object { Write-Host "  $($_.Line)" }
    } else {
        Write-Host "OK  (total / ok / falhas: $($resumo.Line.Trim()))" -ForegroundColor Green
    }
}

if ($falhas -gt 0) { throw "$falhas ficheiro(s) de teste com falhas." }
Write-Host 'Todos os testes SQL passaram.' -ForegroundColor Green
