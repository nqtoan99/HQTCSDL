:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
GO

-- Bổ sung ngữ cảnh để lần theo một nghiệp vụ qua nhiều bảng.
IF COL_LENGTH('dbo.AuditLog','Details') IS NULL
 ALTER TABLE dbo.AuditLog ADD Details nvarchar(1000) NULL;
IF COL_LENGTH('dbo.AuditLog','CorrelationId') IS NULL
 ALTER TABLE dbo.AuditLog ADD CorrelationId uniqueidentifier NULL;
GO

IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.AuditLog') AND name='IX_AuditLog_EntityCreated')
 CREATE INDEX IX_AuditLog_EntityCreated ON dbo.AuditLog(Entity,EntityId,CreatedAt DESC)
 INCLUDE(Action,ActorId,CorrelationId);
GO

CREATE OR ALTER TRIGGER dbo.tr_BookingAudit ON dbo.Bookings AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId,Details,CorrelationId)
 SELECT 'Booking',COALESCE(i.BookingId,d.BookingId),
  CASE WHEN d.BookingId IS NULL THEN 'INSERT' WHEN i.BookingId IS NULL THEN 'DELETE' ELSE 'UPDATE' END,
  TRY_CONVERT(int,SESSION_CONTEXT(N'ActorId')),
  CONCAT(N'Cruise=',COALESCE(i.CruiseId,d.CruiseId),N'; Passenger=',COALESCE(i.PassengerId,d.PassengerId),
         N'; Cabin=',COALESCE(i.CabinId,d.CabinId),N'; Package=',COALESCE(i.PackageId,d.PackageId)),
  COALESCE(TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),NEWID())
 FROM inserted i FULL JOIN deleted d ON d.BookingId=i.BookingId;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_AccountAudit ON dbo.Accounts AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId,Details,CorrelationId)
 SELECT 'Account',COALESCE(i.AccountId,d.AccountId),
  CASE WHEN d.AccountId IS NULL THEN 'INSERT' WHEN i.AccountId IS NULL THEN 'DELETE' ELSE 'UPDATE' END,
  TRY_CONVERT(int,SESSION_CONTEXT(N'ActorId')),
  CONCAT(N'Booking=',COALESCE(i.BookingId,d.BookingId),N'; Status=',COALESCE(i.Status,d.Status)),
  COALESCE(TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),NEWID())
 FROM inserted i FULL JOIN deleted d ON d.AccountId=i.AccountId;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_InvoiceAudit ON dbo.Invoices AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId,Details,CorrelationId)
 SELECT 'Invoice',COALESCE(i.InvoiceId,d.InvoiceId),
  CASE WHEN d.InvoiceId IS NULL THEN 'INSERT' WHEN i.InvoiceId IS NULL THEN 'DELETE' ELSE 'UPDATE' END,
  TRY_CONVERT(int,SESSION_CONTEXT(N'ActorId')),
  CONCAT(N'Account=',COALESCE(i.AccountId,d.AccountId),N'; Total=',COALESCE(i.Total,d.Total)),
  COALESCE(TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),NEWID())
 FROM inserted i FULL JOIN deleted d ON d.InvoiceId=i.InvoiceId;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_PaymentAudit ON dbo.Payments AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId,Details,CorrelationId)
 SELECT 'Payment',COALESCE(i.PaymentId,d.PaymentId),
  CASE WHEN d.PaymentId IS NULL THEN 'INSERT' WHEN i.PaymentId IS NULL THEN 'DELETE' ELSE 'UPDATE' END,
  TRY_CONVERT(int,SESSION_CONTEXT(N'ActorId')),
  CONCAT(N'Invoice=',COALESCE(i.InvoiceId,d.InvoiceId),N'; Amount=',COALESCE(i.Amount,d.Amount),
         N'; Method=',COALESCE(i.Method,d.Method)),
  COALESCE(TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),NEWID())
 FROM inserted i FULL JOIN deleted d ON d.PaymentId=i.PaymentId;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_IdentifierAudit ON dbo.Identifiers AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId,Details,CorrelationId)
 SELECT 'Identifier',COALESCE(i.IdentifierId,d.IdentifierId),
  CASE WHEN d.IdentifierId IS NULL THEN 'INSERT' WHEN i.IdentifierId IS NULL THEN 'DELETE' ELSE 'UPDATE' END,
  TRY_CONVERT(int,SESSION_CONTEXT(N'ActorId')),
  CONCAT(N'Booking=',COALESCE(i.BookingId,d.BookingId),N'; Kind=',COALESCE(i.Kind,d.Kind),
         N'; Active=',COALESCE(i.Active,d.Active)),
  COALESCE(TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),NEWID())
 FROM inserted i FULL JOIN deleted d ON d.IdentifierId=i.IdentifierId;
END;
GO
