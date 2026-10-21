# Testa o hook sql-so-leitura.ps1: os casos "PERMITIDO" têm de sair com código 0 e os "BLOQUEADO" com código 2.
# Uso:  powershell -NoProfile -ExecutionPolicy RemoteSigned -File .claude\hooks\testar-hook.ps1
# Termina com código 0 se todos os casos passarem e com o número de falhas se algum falhar.
$hook = Join-Path $PSScriptRoot 'sql-so-leitura.ps1'

# Lê do próprio hook a primeira base autorizada, para o teste não depender do nome de nenhum cliente.
$m = [regex]::Match((Get-Content $hook -Raw), "basesPermitidas\s*=\s*@\('([^']+)'")
if (-not $m.Success) { Write-Host 'FALHA: não encontrei $basesPermitidas no hook.'; exit 1 }
$ok = $m.Groups[1].Value

$casos = @(
    @{ nome = 'SELECT simples';              esperado = 0; cmd = "sqlcmd -S srv -d $ok -E -Q `"SELECT DB_NAME()`"" },
    @{ nome = 'consulta a sys.triggers';     esperado = 0; cmd = "sqlcmd -S srv -d $ok -E -Q `"SELECT name FROM sys.triggers`"" },
    @{ nome = 'coluna com nome parecido';    esperado = 0; cmd = "sqlcmd -S srv -d $ok -E -Q `"SELECT created_at FROM cl`"" },
    @{ nome = 'DELETE';                      esperado = 2; cmd = "sqlcmd -S srv -d $ok -E -Q `"DELETE FROM cl`"" },
    @{ nome = 'SELECT INTO';                 esperado = 2; cmd = "sqlcmd -S srv -d $ok -E -Q `"SELECT * INTO x FROM cl`"" },
    @{ nome = 'EXEC';                        esperado = 2; cmd = "sqlcmd -S srv -d $ok -E -Q `"EXEC sp_who`"" },
    @{ nome = 'base fora da lista';          esperado = 2; cmd = 'sqlcmd -S srv -d BaseForaDaLista_XYZ -E -Q "SELECT 1"' },
    @{ nome = 'sem indicar a base';          esperado = 2; cmd = 'sqlcmd -S srv -E -Q "SELECT 1"' },
    @{ nome = 'comando encadeado';           esperado = 2; cmd = "sqlcmd -S srv -d $ok -E -Q `"SELECT 1`" && del x" },
    @{ nome = 'script em ficheiro (-i)';     esperado = 2; cmd = "sqlcmd -S srv -d $ok -E -i x.sql" },
    @{ nome = 'outro comando';               esperado = 2; cmd = 'dir' }
)

$falhas = 0
foreach ($c in $casos) {
    $json = @{ tool_input = @{ command = $c.cmd } } | ConvertTo-Json -Compress
    $json | powershell -NoProfile -ExecutionPolicy RemoteSigned -File $hook 2>$null
    $codigo = $LASTEXITCODE
    if ($codigo -eq $c.esperado) { Write-Host "PASSOU  $($c.nome)" }
    else { Write-Host "FALHOU  $($c.nome): esperado $($c.esperado), obtido $codigo"; $falhas++ }
}
if ($falhas -eq 0) { Write-Host 'Hook OK.' } else { Write-Host "$falhas falha(s)." }
exit $falhas
