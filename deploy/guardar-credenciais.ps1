<#
.SYNOPSIS
    Guarda a connection string da base de dados e o token da API protegidos com DPAPI (âmbito da máquina).

.DESCRIPTION
    - Pede os valores sem os mostrar no ecrã (SecureString). Nunca os escreve em texto simples.
    - O ficheiro só pode ser lido NESTE servidor (DPAPI LocalMachine): copiado para outro, não abre.
    - O formato é o que o serviço espera (ver CredentialProvider.cs): JSON protegido com a entropia
      "SigmaCode.Landeiro.CrmSync.v1".
    - Restringe o acesso ao ficheiro a SYSTEM, Administradores, o utilizador atual e (opcional) a conta do serviço.
    Correr numa consola de Administrador, no servidor onde o serviço vai ficar.

.EXAMPLE
    .\guardar-credenciais.ps1
    .\guardar-credenciais.ps1 -ContaServico 'DOMINIO\svc_crmsync'
#>
[CmdletBinding()]
param(
    [string]$Caminho = 'C:\ProgramData\SigmaCode\CrmSync\credenciais.dpapi',
    [string]$ContaServico,
    # Só para automatização/testes: se omitidos, são pedidos de forma segura
    [SecureString]$ConnectionString,
    [SecureString]$Token
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security   # ProtectedData (DPAPI)

function ConvertTo-PlainText([SecureString]$secure) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

if (-not $ConnectionString) { $ConnectionString = Read-Host 'Connection string da base de dados (não aparece no ecrã)' -AsSecureString }
if (-not $Token) { $Token = Read-Host 'Token da API Somnia (não aparece no ecrã)' -AsSecureString }

$db = ConvertTo-PlainText $ConnectionString
$tok = ConvertTo-PlainText $Token
if ([string]::IsNullOrWhiteSpace($db) -or [string]::IsNullOrWhiteSpace($tok)) { throw 'A connection string e o token são obrigatórios.' }

# Os nomes das propriedades têm de ser exatamente estes (o serviço lê com maiúsculas/minúsculas)
$json = [ordered]@{ DbConnectionString = $db; ApiToken = $tok } | ConvertTo-Json -Compress
$entropia = [Text.Encoding]::UTF8.GetBytes('SigmaCode.Landeiro.CrmSync.v1')
$protegido = [Security.Cryptography.ProtectedData]::Protect(
    [Text.Encoding]::UTF8.GetBytes($json), $entropia, [Security.Cryptography.DataProtectionScope]::LocalMachine)

$pasta = Split-Path -Parent $Caminho
New-Item -ItemType Directory -Force -Path $pasta | Out-Null
[IO.File]::WriteAllBytes($Caminho, $protegido)

# Só quem precisa consegue ler o ficheiro
$acl = Get-Acl $Caminho
$acl.SetAccessRuleProtection($true, $false)   # corta a herança
# SIDs universais: os nomes "Administrators"/"SYSTEM" mudam com o idioma do Windows (ex.: "Administradores")
$contas = @(
    (New-Object Security.Principal.SecurityIdentifier('S-1-5-18')),        # SYSTEM
    (New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')),    # Administradores
    [Security.Principal.WindowsIdentity]::GetCurrent().User                # o utilizador que está a correr o script
)
if ($ContaServico) { $contas += (New-Object Security.Principal.NTAccount($ContaServico)) }
foreach ($conta in $contas) {
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($conta, 'FullControl', 'Allow')))
}
Set-Acl -Path $Caminho -AclObject $acl

# Não deixa os segredos em memória nem em variáveis da sessão
$db = $null; $tok = $null; $json = $null
Write-Host "Credenciais guardadas (protegidas por DPAPI) em: $Caminho" -ForegroundColor Green
Write-Host 'Lembrete: a password do utilizador SQL tem de ser trocada antes de produção (docs/pendencias.md).'
