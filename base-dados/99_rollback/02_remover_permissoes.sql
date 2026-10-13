-- Rollback 2/5: remove o papel do serviço (e os seus membros, se existirem).
SET NOCOUNT ON;
GO
IF DATABASE_PRINCIPAL_ID(N'crmsync_servico') IS NOT NULL
BEGIN
    DECLARE @sql nvarchar(max) = N'';
    SELECT @sql += N'ALTER ROLE crmsync_servico DROP MEMBER ' + QUOTENAME(m.name) + N'; '
      FROM sys.database_role_members AS rm
      JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id AND r.name = N'crmsync_servico'
      JOIN sys.database_principals AS m ON m.principal_id = rm.member_principal_id;
    EXEC (@sql);
    DROP ROLE crmsync_servico;
END
GO
