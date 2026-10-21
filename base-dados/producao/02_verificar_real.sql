-- PASSO 4/7: so le (SELECT). Corre na LAND2 depois de gravar/apagar um cliente e um contacto de teste no PHC.
USE LAND2;
GO
SELECT DB_NAME() AS base;
-- Triggers nossos que ainda existem (depois do passo 6 deve vir vazio):
SELECT name AS trigger_nosso FROM sys.triggers WITH (NOLOCK) WHERE name LIKE 'tr[_]crm[_]%';
-- Ultimos 15 registos da fila (o teu cliente/contacto de teste deve aparecer em cima, PENDENTE):
SELECT TOP 15 datacriacao, origem, entidade, codigo, operacao, estado, stamporigem
FROM dbo.u_crmfila WITH (NOLOCK) ORDER BY datacriacao DESC;
-- Resumo por estado:
SELECT estado, COUNT(*) AS total FROM dbo.u_crmfila WITH (NOLOCK) GROUP BY estado;
