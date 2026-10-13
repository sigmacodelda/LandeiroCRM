<#
.SYNOPSIS
    Pára e remove o Windows Service. NÃO apaga a fila, os logs nem as credenciais.

.EXAMPLE
    .\desinstalar-servico.ps1
    .\desinstalar-servico.ps1 -ApagarFicheiros     # apaga também a pasta de instalação (não os logs se estiverem fora dela)
#>
[CmdletBinding()]
param(
    [string]$Nome = 'SigmaCode.Landeiro.CrmSync',
    [string]$Destino = 'C:\SigmaCode\CrmSync',
    [switch]$ApagarFicheiros
)

$ErrorActionPreference = 'Stop'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Correr esta consola como Administrador.' }

$servico = Get-Service -Name $Nome -ErrorAction SilentlyContinue
if (-not $servico) { Write-Host "O serviço $Nome não existe. Nada a fazer."; return }

if ($servico.Status -ne 'Stopped') {
    Write-Host 'A parar o serviço (termina o lote em curso)...' -ForegroundColor Cyan
    Stop-Service -Name $Nome -Force
    $servico.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
}
& sc.exe delete $Nome | Out-Null
Write-Host "Serviço $Nome removido." -ForegroundColor Green

if ($ApagarFicheiros -and (Test-Path $Destino)) {
    Remove-Item -Path $Destino -Recurse -Force
    Write-Host "Pasta $Destino apagada."
}
Write-Host 'A fila u_crmfila, as credenciais e os logs não foram tocados.'
