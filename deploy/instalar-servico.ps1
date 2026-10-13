<#
.SYNOPSIS
    Instala o serviço como Windows Service (arranque automático, reinício automático em caso de falha).

.DESCRIPTION
    Requer consola de Administrador. Antes de instalar, confirma que o executável existe e (se o
    serviço for dependente do framework) que o runtime .NET 8 está instalado no servidor.
    NÃO inicia o serviço sem -Iniciar: primeiro correr guardar-credenciais.ps1.

.EXAMPLE
    .\instalar-servico.ps1 -Origem .\publish -Destino C:\SigmaCode\CrmSync
    .\instalar-servico.ps1 -Origem .\publish -Destino C:\SigmaCode\CrmSync -Iniciar
#>
[CmdletBinding()]
param(
    [string]$Origem = (Join-Path $PSScriptRoot 'publish'),
    [string]$Destino = 'C:\SigmaCode\CrmSync',
    [string]$Nome = 'SigmaCode.Landeiro.CrmSync',
    # Por defeito corre como LocalSystem. Para uma conta dedicada: -Conta 'DOMINIO\svc' (pede a password)
    [string]$Conta,
    [switch]$Iniciar
)

$ErrorActionPreference = 'Stop'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Correr esta consola como Administrador.' }
if (-not (Test-Path (Join-Path $Origem 'SigmaCode.Landeiro.CrmSync.Worker.exe'))) { throw "Não encontrei o serviço publicado em $Origem. Correr primeiro publicar.ps1." }

# Se a publicação for dependente do framework, o runtime 8 tem de existir no servidor
$autoContido = Test-Path (Join-Path $Origem 'hostfxr.dll')
if (-not $autoContido) {
    $runtimes = & dotnet --list-runtimes 2>$null
    if (-not ($runtimes -match 'Microsoft\.NETCore\.App 8\.')) {
        throw 'Falta o runtime .NET 8 (Microsoft.NETCore.App 8.x) neste servidor. Instalar o .NET 8 Runtime ou publicar com -AutoContido.'
    }
}

if (Get-Service -Name $Nome -ErrorAction SilentlyContinue) {
    throw "O serviço $Nome já existe. Para atualizar: desinstalar-servico.ps1, copiar os ficheiros e instalar de novo (as credenciais e os logs mantêm-se)."
}

Write-Host "A copiar para $Destino ..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $Destino | Out-Null
Copy-Item -Path (Join-Path $Origem '*') -Destination $Destino -Recurse -Force

$exe = Join-Path $Destino 'SigmaCode.Landeiro.CrmSync.Worker.exe'
$parametros = @{
    Name           = $Nome
    BinaryPathName = "`"$exe`""
    DisplayName    = 'SigmaCode - Integração PHC > Somnia CRM (Carnes Landeiro)'
    Description    = 'Envia clientes e contactos do PHC para o Somnia CRM (fila u_crmfila).'
    StartupType    = 'Automatic'
}
if ($Conta) { $parametros.Credential = Get-Credential -UserName $Conta -Message "Password da conta do serviço $Conta" }
New-Service @parametros | Out-Null

# Reinicia sozinho se falhar (1 min, 1 min, 1 min) e repõe o contador ao fim de 1 dia
& sc.exe failure $Nome reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null

Write-Host "Serviço $Nome instalado em $Destino (ainda parado)." -ForegroundColor Green
if ($Iniciar) {
    Start-Service -Name $Nome
    Write-Host 'Serviço iniciado.' -ForegroundColor Green
} else {
    Write-Host 'Para iniciar: guardar-credenciais.ps1 e depois  Start-Service ' -NoNewline
    Write-Host $Nome
}
