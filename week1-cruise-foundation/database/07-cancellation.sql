:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
GO

IF COL_LENGTH('dbo.Policy','RefundPercent') IS NULL
 ALTER TABLE dbo.Policy ADD RefundPercent int NOT NULL CONSTRAINT DF_Policy_RefundPercent DEFAULT 100 WITH VALUES;
GO
IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE name='CK_Policy_RefundPercent')
 ALTER TABLE dbo.Policy ADD CONSTRAINT CK_Policy_RefundPercent CHECK(RefundPercent BETWEEN 0 AND 100);
GO

IF COL_LENGTH('dbo.Registrations','CancelledAt') IS NULL
 ALTER TABLE dbo.Registrations ADD CancelledAt datetime2 NULL;
IF COL_LENGTH('dbo.Registrations','CancelledBy') IS NULL
 ALTER TABLE dbo.Registrations ADD CancelledBy int NULL REFERENCES dbo.Users(UserId);
IF COL_LENGTH('dbo.Registrations','CancelReason') IS NULL
 ALTER TABLE dbo.Registrations ADD CancelReason nvarchar(500) NULL;
IF COL_LENGTH('dbo.Registrations','RefundAmount') IS NULL
 ALTER TABLE dbo.Registrations ADD RefundAmount decimal(18,2) NULL;
GO
IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE name='CK_Registrations_RefundAmount')
 ALTER TABLE dbo.Registrations ADD CONSTRAINT CK_Registrations_RefundAmount CHECK(RefundAmount IS NULL OR RefundAmount>=0);
GO

IF COL_LENGTH('dbo.Transactions','RefundAmount') IS NULL
 ALTER TABLE dbo.Transactions ADD RefundAmount decimal(18,2) NULL;
IF COL_LENGTH('dbo.Transactions','RefundedAt') IS NULL
 ALTER TABLE dbo.Transactions ADD RefundedAt datetime2 NULL;
IF COL_LENGTH('dbo.Transactions','RefundedBy') IS NULL
 ALTER TABLE dbo.Transactions ADD RefundedBy int NULL REFERENCES dbo.Users(UserId);
GO
IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE name='CK_Transactions_RefundAmount')
 ALTER TABLE dbo.Transactions ADD CONSTRAINT CK_Transactions_RefundAmount CHECK(RefundAmount IS NULL OR (RefundAmount>=0 AND RefundAmount<=Amount));
GO

CREATE OR ALTER PROCEDURE dbo.usp_CancelRegistration
 @RegistrationId int,
 @ActorId int,
 @Reason nvarchar(500)
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;

  DECLARE @BookingId int,@RegistrationStatus varchar(20),@StartsAt datetime2,
          @CancelHours int,@RefundPercent int,@AccountStatus varchar(10),
          @TransactionId int,@TransactionStatus varchar(20),@Amount decimal(18,2),
          @RefundAmount decimal(18,2)=0;

  SELECT @BookingId=r.BookingId,@RegistrationStatus=r.Status,@StartsAt=a.StartsAt,
         @CancelHours=p.CancelHours,@RefundPercent=p.RefundPercent,@AccountStatus=ac.Status
  FROM dbo.Registrations r WITH(UPDLOCK,HOLDLOCK)
  JOIN dbo.Activities a WITH(UPDLOCK,HOLDLOCK) ON a.ActivityId=r.ActivityId
  JOIN dbo.Accounts ac WITH(UPDLOCK,HOLDLOCK) ON ac.BookingId=r.BookingId
  CROSS JOIN dbo.Policy p
  WHERE r.RegistrationId=@RegistrationId AND p.PolicyId=1;

  IF @BookingId IS NULL THROW 51270,N'Đăng ký không tồn tại.',1;
  IF @Reason IS NULL OR LEN(LTRIM(RTRIM(@Reason)))=0 OR LEN(@Reason)>500
   THROW 51271,N'Lý do hủy không hợp lệ.',1;

  IF NOT EXISTS(
   SELECT 1 FROM dbo.Bookings b
   JOIN dbo.Passengers p ON p.PassengerId=b.PassengerId
   WHERE b.BookingId=@BookingId AND p.UserId=@ActorId
  ) AND NOT EXISTS(
   SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles ro ON ro.RoleId=ur.RoleId
   WHERE ur.UserId=@ActorId AND ro.Code='ADMIN'
  ) THROW 51272,N'Không có quyền hủy đăng ký này.',1;

  IF @RegistrationStatus='CANCELLED' THROW 51273,N'Đăng ký đã được hủy trước đó.',1;
  IF EXISTS(SELECT 1 FROM dbo.CheckIns WHERE RegistrationId=@RegistrationId)
   THROW 51274,N'Không thể hủy sau khi hành khách đã check-in.',1;
  IF SYSDATETIME()>DATEADD(hour,-@CancelHours,@StartsAt)
   THROW 51275,N'Đã quá hạn hủy theo chính sách.',1;
  IF @AccountStatus<>'OPEN' THROW 51276,N'Tài khoản booking đã chốt, không thể hoàn phí.',1;

  IF @RegistrationStatus='CONFIRMED'
  BEGIN
   SELECT @TransactionId=TransactionId,@TransactionStatus=Status,@Amount=Amount
   FROM dbo.Transactions WITH(UPDLOCK,HOLDLOCK)
   WHERE RegistrationId=@RegistrationId;
   IF @TransactionId IS NULL THROW 51277,N'Không tìm thấy giao dịch của đăng ký đã xác nhận.',1;
   IF @TransactionStatus<>'POSTED' THROW 51278,N'Giao dịch không còn ở trạng thái có thể hoàn phí.',1;
   SET @RefundAmount=ROUND(@Amount*@RefundPercent/100.0,2);
  END

  EXEC sys.sp_set_session_context @key=N'ActorId',@value=@ActorId;
  UPDATE dbo.Registrations
  SET Status='CANCELLED',CancelledAt=SYSUTCDATETIME(),CancelledBy=@ActorId,
      CancelReason=LTRIM(RTRIM(@Reason)),RefundAmount=@RefundAmount
  WHERE RegistrationId=@RegistrationId;

  IF @TransactionId IS NOT NULL
   UPDATE dbo.Transactions
   SET Status='REFUNDED',RefundAmount=@RefundAmount,RefundedAt=SYSUTCDATETIME(),RefundedBy=@ActorId
   WHERE TransactionId=@TransactionId;

  COMMIT;
  SELECT @RegistrationId AS RegistrationId,'CANCELLED' AS Status,
         @RefundAmount AS RefundAmount,@RefundPercent AS RefundPercent;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
 END CATCH
END;
GO
