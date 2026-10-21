# Hook PreToolUse do agente sc-leitor-bd.
# O que faz: recebe o comando Bash que o agente quer correr e bloqueia tudo o que não seja
# uma consulta de leitura (sqlcmd com SELECT) a uma base de testes autorizada.
# Como bloqueia: escreve o motivo no stderr e sai com código 2 (o Claude Code cancela a chamada).

# Bases onde a leitura é permitida. Acrescentar aqui as bases de teste de cada cliente.
$basesPermitidas = @('DemoSigmaCode')

# Lê o JSON que o Claude Code envia pelo stdin e extrai o comando.
$entrada = [Console]::In.ReadToEnd() | ConvertFrom-Json
$cmd = [string]$entrada.tool_input.command

function Bloquear([string]$motivo) {
    [Console]::Error.WriteLine("BLOQUEADO (sql-so-leitura): $motivo")
    exit 2
}

# 1. Só se permite sqlcmd.
if ($cmd -notmatch '^\s*sqlcmd(\.exe)?\s') { Bloquear 'só é permitido o comando sqlcmd.' }

# 2. Sem encadear comandos nem redirecionar (shell). Por isso nas consultas usar != em vez de <>.
if ($cmd -match '(&&|\|\||\||>|<|`|\$\()') { Bloquear 'não é permitido encadear comandos nem redirecionar (usar != em vez de <>).' }

# 3. A base tem de vir indicada (-d) e estar na lista autorizada.
if ($cmd -cmatch '(^|\s)-d\s+"?([A-Za-z0-9_]+)"?') { $base = $Matches[2] } else { Bloquear 'falta indicar a base com -d.' }
if ($basesPermitidas -notcontains $base) { Bloquear "a base '$base' não está na lista de bases de teste autorizadas." }

# 4. Só consultas de leitura: tem de haver -Q (consulta) e nenhuma palavra de escrita.
if ($cmd -cnotmatch '(^|\s)-Q\s') { Bloquear 'a consulta tem de vir em -Q (não são permitidos scripts com -i).' }
$proibidas = 'INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|CREATE|TRUNCATE|EXEC|EXECUTE|GRANT|REVOKE|DENY|BACKUP|RESTORE|SHUTDOWN|KILL|OPENROWSET|OPENQUERY|BULK|WAITFOR|INTO|xp_\w+|sp_\w+'
if ($cmd -match "(?i)\b($proibidas)\b") { Bloquear 'a consulta tem uma palavra que não é de leitura.' }

# 5. Permitido.
exit 0
