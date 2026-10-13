# deploy

Scripts PowerShell 5.1 (consola de **Administrador** onde indicado). Ver [../docs/manual-instalacao.md](../docs/manual-instalacao.md).

| Script | Para quê |
|---|---|
| `publicar.ps1` | Corre os testes unitários e publica o serviço (`-AutoContido` leva o runtime .NET). |
| `guardar-credenciais.ps1` | Guarda a connection string e o token **protegidos por DPAPI** (pede-os sem os mostrar). |
| `instalar-servico.ps1` | Copia e instala o Windows Service (arranque automático, reinício em falha). Não o inicia sem `-Iniciar`. |
| `desinstalar-servico.ps1` | Pára e remove o serviço. Não apaga fila, logs nem credenciais. |
| `reiniciar-servico.ps1` | Reinicia o serviço (ao arrancar repõe a PENDENTE o que estava A_PROCESSAR). |

Nada aqui contém segredos. `publish/` (resultado da publicação) está fora do git.
