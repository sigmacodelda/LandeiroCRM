<#
.SYNOPSIS
    Compila e publica o serviço (Release) para uma pasta, pronta a copiar para o servidor PHC.

.DESCRIPTION
    Por defeito publica "dependente do framework": o servidor precisa do runtime .NET 8
    (Microsoft.NETCore.App 8.x). Com -AutoContido leva o runtime junto (pasta maior, sem pré-requisitos).
    Corre os testes unitários antes de publicar (a não ser que se use -SemTestes).

.EXAMPLE
    .\publicar.ps1
    .\publicar.ps1 -Destino C:\Temp\crmsync -AutoContido
#>
[CmdletBinding()]
param(
    [string]$Destino = (Join-Path $PSScriptRoot 'publish'),
    [switch]$AutoContido,
    [switch]$SemTestes
)

$ErrorActionPreference = 'Stop'
$solucao = Join-Path $PSScriptRoot '..\servico\SigmaCode.Landeiro.CrmSync.sln'
$projeto = Join-Path $PSScriptRoot '..\servico\src\SigmaCode.Landeiro.CrmSync.Worker\SigmaCode.Landeiro.CrmSync.Worker.csproj'

if (-not $SemTestes) {
    Write-Host '1/2 A correr os testes unitários...' -ForegroundColor Cyan
    # Só os testes do Core: não precisam de base de dados. Os de integração correm à parte (ver docs/plano-de-testes.md).
    dotnet test (Join-Path $PSScriptRoot '..\servico\tests\SigmaCode.Landeiro.CrmSync.Core.Tests') --nologo
    if ($LASTEXITCODE -ne 0) { throw 'Os testes falharam: a publicação foi cancelada.' }
}

Write-Host "2/2 A publicar para $Destino ..." -ForegroundColor Cyan
$modo = if ($AutoContido) { '--self-contained', 'true', '-r', 'win-x64' } else { '--self-contained', 'false' }
dotnet publish $projeto -c Release -o $Destino @modo --nologo
if ($LASTEXITCODE -ne 0) { throw 'A publicação falhou.' }

# Nunca publicar segredos nem ficheiros de desenvolvimento
Get-ChildItem $Destino -Include 'appsettings.Development.json', '*.pdb' -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force

Write-Host "Publicado em: $Destino" -ForegroundColor Green
Write-Host 'Próximo passo: copiar para o servidor e correr guardar-credenciais.ps1 e instalar-servico.ps1.'
