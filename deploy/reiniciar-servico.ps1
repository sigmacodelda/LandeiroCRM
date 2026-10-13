<#
.SYNOPSIS
    Reinicia o serviço (por exemplo, depois de mudar o appsettings.json ou as credenciais).
    Ao arrancar, o serviço repõe a PENDENTE o que tenha ficado em A_PROCESSAR.
#>
[CmdletBinding()]
param([string]$Nome = 'SigmaCode.Landeiro.CrmSync')

$ErrorActionPreference = 'Stop'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Correr esta consola como Administrador.' }

Restart-Service -Name $Nome -Force
(Get-Service -Name $Nome) | Format-Table Name, Status -AutoSize
