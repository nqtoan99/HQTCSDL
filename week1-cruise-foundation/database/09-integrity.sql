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

IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Bookings') AND name='IX_Bookings_CruiseCabin')
 CREATE INDEX IX_Bookings_CruiseCabin ON dbo.Bookings(CruiseId,CabinId) INCLUDE(PassengerId,PackageId);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Transactions') AND name='IX_Transactions_RegistrationAccount')
 CREATE INDEX IX_Transactions_RegistrationAccount ON dbo.Transactions(RegistrationId,AccountId)
 WHERE RegistrationId IS NOT NULL;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.AuditLog') AND name='IX_AuditLog_Correlation')
 CREATE INDEX IX_AuditLog_Correlation ON dbo.AuditLog(CorrelationId,CreatedAt) WHERE CorrelationId IS NOT NULL;
GO

CREATE OR ALTER TRIGGER dbo.tr_BookingConsistency ON dbo.Bookings AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(
  SELECT 1 FROM inserted b
  JOIN dbo.Cruises c ON c.CruiseId=b.CruiseId
  JOIN dbo.Cabins cb ON cb.CabinId=b.CabinId
  WHERE cb.ShipId<>c.ShipId
 ) THROW 51330,N'Cabin phải thuộc tàu của chuyến trong booking.',1;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_ActivityConsistency ON dbo.Activities AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(
  SELECT 1 FROM inserted a
  JOIN dbo.Cruises c ON c.CruiseId=a.CruiseId
  LEFT JOIN dbo.Zones z ON z.ZoneId=a.ZoneId
  LEFT JOIN dbo.Stops s ON s.StopId=a.StopId
  WHERE (a.Kind='ONBOARD' AND z.ShipId<>c.ShipId)
     OR (a.Kind='SHORE' AND (s.CruiseId<>a.CruiseId OR a.StartsAt<s.Arrival OR a.ReturnAt>s.Departure))
 ) THROW 51331,N'Khu vực hoặc điểm dừng của hoạt động không khớp chuyến và thời gian cảng.',1;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_TransactionConsistency ON dbo.Transactions AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(
  SELECT 1 FROM inserted t
  JOIN dbo.Accounts ac ON ac.AccountId=t.AccountId
  LEFT JOIN dbo.Registrations r ON r.RegistrationId=t.RegistrationId
  LEFT JOIN dbo.Devices d ON d.DeviceId=t.DeviceId
  WHERE ac.Status<>'OPEN'
     OR (t.RegistrationId IS NOT NULL AND ac.BookingId<>r.BookingId)
     OR (t.ServiceId IS NOT NULL AND d.Kind<>'POS')
 ) THROW 51332,N'Giao dịch không khớp booking, thiết bị POS hoặc tài khoản đã chốt.',1;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_ProtectSettledTransactions ON dbo.Transactions AFTER DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted d JOIN dbo.Accounts ac ON ac.AccountId=d.AccountId WHERE ac.Status='SETTLED')
  THROW 51333,N'Không được xóa giao dịch của tài khoản đã chốt.',1;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_InvoiceConsistency ON dbo.Invoices AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(
  SELECT 1 FROM deleted d
  JOIN dbo.Accounts ac ON ac.AccountId=d.AccountId
  LEFT JOIN inserted i ON i.InvoiceId=d.InvoiceId
  WHERE ac.Status='SETTLED' AND (i.InvoiceId IS NULL OR i.Total<>d.Total OR i.AccountId<>d.AccountId)
 ) THROW 51334,N'Hóa đơn của tài khoản đã chốt không được sửa hoặc xóa.',1;

 IF EXISTS(
  SELECT 1 FROM inserted i
  JOIN dbo.Accounts ac ON ac.AccountId=i.AccountId
  OUTER APPLY(
   SELECT CONVERT(decimal(18,2),COALESCE(SUM(CASE t.Status
    WHEN 'POSTED' THEN t.Amount
    WHEN 'REFUNDED' THEN t.Amount-COALESCE(t.RefundAmount,0)
    ELSE 0 END),0)) ExpectedTotal
   FROM dbo.Transactions t WHERE t.AccountId=i.AccountId
  ) x
  WHERE ac.Status<>'OPEN' OR i.Total<>x.ExpectedTotal
 ) THROW 51335,N'Tổng hóa đơn không khớp giao dịch hoặc tài khoản không còn mở.',1;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_PaymentConsistency ON dbo.Payments AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(
  SELECT 1 FROM deleted d JOIN dbo.Invoices inv ON inv.InvoiceId=d.InvoiceId
  JOIN dbo.Accounts ac ON ac.AccountId=inv.AccountId
  LEFT JOIN inserted i ON i.PaymentId=d.PaymentId
  WHERE ac.Status='SETTLED' AND (i.PaymentId IS NULL OR i.Amount<>d.Amount OR i.InvoiceId<>d.InvoiceId OR i.Method<>d.Method)
 ) THROW 51336,N'Thanh toán của tài khoản đã chốt không được sửa hoặc xóa.',1;

 IF EXISTS(
  SELECT 1 FROM inserted p JOIN dbo.Invoices inv ON inv.InvoiceId=p.InvoiceId
  JOIN dbo.Accounts ac ON ac.AccountId=inv.AccountId
  WHERE ac.Status<>'OPEN' OR p.Amount<>inv.Total
     OR UPPER(LTRIM(RTRIM(p.Method))) NOT IN('CASH','CARD','TRANSFER','MOCK')
 ) THROW 51337,N'Thanh toán không khớp hóa đơn, phương thức hoặc tài khoản không còn mở.',1;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_AccountSettlementGuard ON dbo.Accounts AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(
  SELECT 1 FROM inserted i JOIN deleted d ON d.AccountId=i.AccountId
  WHERE d.Status='SETTLED' AND (i.Status<>d.Status OR i.BookingId<>d.BookingId)
 ) THROW 51338,N'Tài khoản đã chốt không được mở lại hoặc chuyển booking.',1;

 IF EXISTS(
  SELECT 1 FROM inserted i JOIN deleted d ON d.AccountId=i.AccountId
  WHERE d.Status='OPEN' AND i.Status='SETTLED' AND NOT EXISTS(
   SELECT 1 FROM dbo.Invoices inv JOIN dbo.Payments p ON p.InvoiceId=inv.InvoiceId
   WHERE inv.AccountId=i.AccountId AND p.Amount=inv.Total
  )
 ) THROW 51339,N'Chỉ được chốt tài khoản sau khi có hóa đơn và thanh toán khớp.',1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_VerifyDataIntegrity
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @Violations int=0;
 SELECT @Violations=@Violations+COUNT(*)
 FROM dbo.Bookings b JOIN dbo.Cruises c ON c.CruiseId=b.CruiseId JOIN dbo.Cabins cb ON cb.CabinId=b.CabinId
 WHERE cb.ShipId<>c.ShipId;
 SELECT @Violations=@Violations+COUNT(*)
 FROM dbo.Activities a JOIN dbo.Cruises c ON c.CruiseId=a.CruiseId
 LEFT JOIN dbo.Zones z ON z.ZoneId=a.ZoneId LEFT JOIN dbo.Stops s ON s.StopId=a.StopId
 WHERE (a.Kind='ONBOARD' AND z.ShipId<>c.ShipId)
    OR (a.Kind='SHORE' AND (s.CruiseId<>a.CruiseId OR a.StartsAt<s.Arrival OR a.ReturnAt>s.Departure));
 SELECT @Violations=@Violations+COUNT(*)
 FROM dbo.Transactions t JOIN dbo.Accounts ac ON ac.AccountId=t.AccountId
 LEFT JOIN dbo.Registrations r ON r.RegistrationId=t.RegistrationId
 WHERE t.RegistrationId IS NOT NULL AND ac.BookingId<>r.BookingId;
 SELECT @Violations=@Violations+COUNT(*)
 FROM dbo.Accounts ac LEFT JOIN dbo.Invoices inv ON inv.AccountId=ac.AccountId
 LEFT JOIN dbo.Payments p ON p.InvoiceId=inv.InvoiceId
 WHERE ac.Status='SETTLED' AND (inv.InvoiceId IS NULL OR p.PaymentId IS NULL OR p.Amount<>inv.Total);
 IF @Violations>0 THROW 51340,N'Phát hiện dữ liệu chéo bảng không toàn vẹn.',1;
 SELECT @Violations AS ViolationCount;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_SettleAccount
 @AccountId int,
 @ActorId int,
 @Method varchar(20)
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF NOT EXISTS(
  SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId
  WHERE ur.UserId=@ActorId AND r.Code IN('FINANCE','ADMIN')
 ) THROW 51341,N'Chỉ tài chính hoặc quản trị viên được chốt tài khoản.',1;
 IF UPPER(LTRIM(RTRIM(@Method))) NOT IN('CASH','CARD','TRANSFER','MOCK')
  THROW 51342,N'Phương thức thanh toán không hợp lệ.',1;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @Status varchar(10),@Total decimal(18,2),@InvoiceId int,
          @CorrelationId uniqueidentifier=NEWID();
  SELECT @Status=Status FROM dbo.Accounts WITH(UPDLOCK,HOLDLOCK) WHERE AccountId=@AccountId;
  IF @Status IS NULL THROW 51343,N'Tài khoản không tồn tại.',1;
  IF @Status<>'OPEN' THROW 51344,N'Tài khoản đã được chốt trước đó.',1;
  IF EXISTS(
   SELECT 1 FROM dbo.Disputes d JOIN dbo.Transactions t ON t.TransactionId=d.TransactionId
   WHERE t.AccountId=@AccountId AND d.Status='OPEN'
  ) THROW 51345,N'Phải xử lý hết tranh chấp trước khi chốt tài khoản.',1;
  IF EXISTS(SELECT 1 FROM dbo.Invoices WHERE AccountId=@AccountId)
   THROW 51346,N'Tài khoản đã có hóa đơn.',1;

  SELECT @Total=CONVERT(decimal(18,2),COALESCE(SUM(CASE Status
   WHEN 'POSTED' THEN Amount
   WHEN 'REFUNDED' THEN Amount-COALESCE(RefundAmount,0)
   ELSE 0 END),0))
  FROM dbo.Transactions WITH(UPDLOCK,HOLDLOCK) WHERE AccountId=@AccountId;

  EXEC sys.sp_set_session_context @key=N'ActorId',@value=@ActorId;
  EXEC sys.sp_set_session_context @key=N'CorrelationId',@value=@CorrelationId;
  INSERT dbo.Invoices(AccountId,Total) VALUES(@AccountId,@Total);
  SET @InvoiceId=SCOPE_IDENTITY();
  INSERT dbo.Payments(InvoiceId,Amount,Method) VALUES(@InvoiceId,@Total,UPPER(LTRIM(RTRIM(@Method))));
  UPDATE dbo.Accounts SET Status='SETTLED' WHERE AccountId=@AccountId;
  COMMIT;
  SELECT @AccountId AS AccountId,@InvoiceId AS InvoiceId,@Total AS Total,'SETTLED' AS Status,@CorrelationId AS CorrelationId;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
 END CATCH
END;
GO

EXEC dbo.usp_VerifyDataIntegrity;
GO
