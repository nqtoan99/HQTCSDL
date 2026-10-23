:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
GO

IF COL_LENGTH(N'dbo.Disputes',N'SubmittedAt') IS NULL
 ALTER TABLE dbo.Disputes ADD SubmittedAt datetime2(3) NOT NULL CONSTRAINT DF_Disputes_SubmittedAt DEFAULT SYSUTCDATETIME() WITH VALUES;
IF COL_LENGTH(N'dbo.Disputes',N'SubmittedBy') IS NULL
 ALTER TABLE dbo.Disputes ADD SubmittedBy int NULL REFERENCES dbo.Users(UserId);
IF COL_LENGTH(N'dbo.Disputes',N'ResolvedAt') IS NULL
 ALTER TABLE dbo.Disputes ADD ResolvedAt datetime2(3) NULL;
IF COL_LENGTH(N'dbo.Disputes',N'ResolvedBy') IS NULL
 ALTER TABLE dbo.Disputes ADD ResolvedBy int NULL REFERENCES dbo.Users(UserId);
IF COL_LENGTH(N'dbo.Disputes',N'Resolution') IS NULL
 ALTER TABLE dbo.Disputes ADD Resolution nvarchar(500) NULL;
GO

IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.Disputes') AND name=N'UX_Disputes_Open_Transaction')
 CREATE UNIQUE INDEX UX_Disputes_Open_Transaction ON dbo.Disputes(TransactionId) WHERE Status='OPEN';
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.Disputes') AND name=N'IX_Disputes_SubmittedBy_Date')
 CREATE INDEX IX_Disputes_SubmittedBy_Date ON dbo.Disputes(SubmittedBy,SubmittedAt DESC) INCLUDE(TransactionId,Status);
GO

CREATE OR ALTER TRIGGER dbo.tr_DisputeAudit ON dbo.Disputes AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId,Details,CorrelationId)
 SELECT 'Dispute',COALESCE(i.DisputeId,d.DisputeId),
  CASE WHEN d.DisputeId IS NULL THEN 'INSERT' WHEN i.DisputeId IS NULL THEN 'DELETE' ELSE 'UPDATE' END,
  COALESCE(TRY_CONVERT(int,SESSION_CONTEXT(N'ActorId')),i.SubmittedBy,d.SubmittedBy),
  CONCAT(N'Transaction=',COALESCE(i.TransactionId,d.TransactionId),N'; Status=',COALESCE(i.Status,d.Status),N'; Reason=',COALESCE(i.Reason,d.Reason)),
  COALESCE(TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),NEWID())
 FROM inserted i FULL JOIN deleted d ON d.DisputeId=i.DisputeId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_SubmitPassengerDispute
 @TransactionId int,@PassengerUserId int,@Reason nvarchar(500)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@PassengerUserId AND r.Code='PASSENGER')
  THROW 51500,N'Tài khoản không có vai trò hành khách.',1;
 IF @Reason IS NULL OR LEN(LTRIM(RTRIM(@Reason)))<10 OR LEN(@Reason)>500
  THROW 51501,N'Lý do tranh chấp phải có từ 10 đến 500 ký tự.',1;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @AccountId int,@Status varchar(20),@CorrelationId uniqueidentifier=NEWID(),@DisputeId int;
  SELECT @AccountId=t.AccountId,@Status=t.Status
  FROM dbo.Transactions t WITH(UPDLOCK,HOLDLOCK)
  JOIN dbo.Accounts ac WITH(UPDLOCK,HOLDLOCK) ON ac.AccountId=t.AccountId
  JOIN dbo.Bookings b ON b.BookingId=ac.BookingId
  JOIN dbo.Passengers p ON p.PassengerId=b.PassengerId
  WHERE t.TransactionId=@TransactionId AND p.UserId=@PassengerUserId;
  IF @AccountId IS NULL THROW 51502,N'Không tìm thấy giao dịch thuộc booking của bạn.',1;
  IF @Status NOT IN('POSTED','REFUNDED') THROW 51503,N'Chỉ có thể tranh chấp giao dịch đã ghi nhận hoặc đã hoàn.',1;
  IF EXISTS(SELECT 1 FROM dbo.Disputes WITH(UPDLOCK,HOLDLOCK) WHERE TransactionId=@TransactionId AND Status='OPEN')
   THROW 51504,N'Giao dịch đã có tranh chấp đang chờ xử lý.',1;

  EXEC sys.sp_set_session_context @key=N'ActorId',@value=@PassengerUserId;
  EXEC sys.sp_set_session_context @key=N'CorrelationId',@value=@CorrelationId;
  INSERT dbo.Disputes(TransactionId,Reason,Status,SubmittedBy)
   VALUES(@TransactionId,LTRIM(RTRIM(@Reason)),'OPEN',@PassengerUserId);
  SET @DisputeId=SCOPE_IDENTITY();
  COMMIT;
  SELECT d.DisputeId,d.TransactionId,d.Reason,d.Status,d.SubmittedAt,d.SubmittedBy,d.ResolvedAt,d.ResolvedBy,d.Resolution
  FROM dbo.Disputes d WHERE d.DisputeId=@DisputeId;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
 END CATCH;
END;
GO
