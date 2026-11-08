:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
GO

IF COL_LENGTH('dbo.Policy','RegistrationOpenHours') IS NULL
 ALTER TABLE dbo.Policy ADD RegistrationOpenHours int NOT NULL CONSTRAINT DF_Policy_RegistrationOpenHours DEFAULT 8760 WITH VALUES;
IF COL_LENGTH('dbo.Policy','RegistrationCloseHours') IS NULL
 ALTER TABLE dbo.Policy ADD RegistrationCloseHours int NOT NULL CONSTRAINT DF_Policy_RegistrationCloseHours DEFAULT 0 WITH VALUES;
IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE name='CK_Policy_RegistrationWindow')
 ALTER TABLE dbo.Policy ADD CONSTRAINT CK_Policy_RegistrationWindow CHECK(RegistrationOpenHours BETWEEN 0 AND 8760 AND RegistrationCloseHours BETWEEN 0 AND 8760 AND RegistrationOpenHours>RegistrationCloseHours);
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminSavePolicy
 @ActorId int,@CancelHours int,@RefundPercent int,
 @RegistrationOpenHours int=8760,@RegistrationCloseHours int=0
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF NOT EXISTS(SELECT 1 FROM dbo.Users actor JOIN dbo.UserRoles ur ON ur.UserId=actor.UserId JOIN dbo.Roles r ON r.RoleId=ur.RoleId WHERE actor.UserId=@ActorId AND actor.Active=1 AND r.Code='ADMIN')
  THROW 51280,N'Chỉ quản trị viên được sửa chính sách.',1;
 IF @CancelHours<0 OR @CancelHours>8760 OR @RefundPercent<0 OR @RefundPercent>100 OR
    @RegistrationOpenHours<0 OR @RegistrationOpenHours>8760 OR @RegistrationCloseHours<0 OR @RegistrationCloseHours>8760 OR
    @RegistrationOpenHours<=@RegistrationCloseHours
  THROW 51315,N'Chính sách hủy, hoàn phí hoặc thời gian đăng ký không hợp lệ.',1;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @CorrelationId uniqueidentifier=NEWID();
  EXEC sys.sp_set_session_context @key=N'ActorId',@value=@ActorId;
  EXEC sys.sp_set_session_context @key=N'CorrelationId',@value=@CorrelationId;
  UPDATE dbo.Policy SET CancelHours=@CancelHours,RefundPercent=@RefundPercent,
   RegistrationOpenHours=@RegistrationOpenHours,RegistrationCloseHours=@RegistrationCloseHours WHERE PolicyId=1;
  IF @@ROWCOUNT=0 THROW 51321,N'Chính sách chưa được khởi tạo.',1;
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_PolicyAudit ON dbo.Policy AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId,Details,CorrelationId)
 SELECT 'Policy',i.PolicyId,'UPDATE',TRY_CONVERT(int,SESSION_CONTEXT(N'ActorId')),
  CONCAT(N'CancelHours=',d.CancelHours,N'→',i.CancelHours,N'; RefundPercent=',d.RefundPercent,N'→',i.RefundPercent,
   N'; RegistrationOpenHours=',d.RegistrationOpenHours,N'→',i.RegistrationOpenHours,
   N'; RegistrationCloseHours=',d.RegistrationCloseHours,N'→',i.RegistrationCloseHours),
  COALESCE(TRY_CONVERT(uniqueidentifier,SESSION_CONTEXT(N'CorrelationId')),NEWID())
 FROM inserted i JOIN deleted d ON d.PolicyId=i.PolicyId
 WHERE i.CancelHours<>d.CancelHours OR i.RefundPercent<>d.RefundPercent OR
  i.RegistrationOpenHours<>d.RegistrationOpenHours OR i.RegistrationCloseHours<>d.RegistrationCloseHours;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Register
 @BookingId int,@ActivityId int,@ActorId int
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @CruiseId int,@Capacity int,@Fee decimal(18,2),@StartsAt datetime2,
   @ActivityStatus varchar(20),@IncludedServiceId int,@AccountId int,@PackageId int,
   @BookingCruiseId int,@Price decimal(18,2),@RegistrationStatus varchar(20),
   @OpenHours int,@CloseHours int,@Now datetime2=SYSDATETIME();
  SELECT @CruiseId=a.CruiseId,@Capacity=a.Capacity,@Fee=a.Fee,@StartsAt=a.StartsAt,
   @ActivityStatus=a.Status,@IncludedServiceId=a.IncludedServiceId
  FROM dbo.Activities a WITH(UPDLOCK,HOLDLOCK) WHERE a.ActivityId=@ActivityId;
  IF @CruiseId IS NULL THROW 51262,N'Hoạt động không tồn tại.',1;
  SELECT @OpenHours=RegistrationOpenHours,@CloseHours=RegistrationCloseHours FROM dbo.Policy WHERE PolicyId=1;
  IF @ActivityStatus<>'OPEN' OR @Now<DATEADD(HOUR,-@OpenHours,@StartsAt) OR @Now>=DATEADD(HOUR,-@CloseHours,@StartsAt)
   THROW 51263,N'Hoạt động chưa mở đăng ký hoặc đã quá thời hạn đăng ký.',1;
  SELECT @BookingCruiseId=b.CruiseId,@PackageId=b.PackageId FROM dbo.Bookings b
   JOIN dbo.Cruises c ON c.CruiseId=b.CruiseId AND c.Status<>'CLOSED' WHERE b.BookingId=@BookingId;
  IF @BookingCruiseId IS NULL OR @BookingCruiseId<>@CruiseId THROW 51264,N'Booking không thuộc chuyến đang mở của hoạt động.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Bookings b JOIN dbo.Passengers p ON p.PassengerId=b.PassengerId WHERE b.BookingId=@BookingId AND p.UserId=@ActorId)
   AND NOT EXISTS(SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@ActorId AND r.Code='ADMIN')
   THROW 51265,N'Không có quyền đăng ký cho booking này.',1;
  IF EXISTS(SELECT 1 FROM dbo.Registrations WHERE BookingId=@BookingId AND ActivityId=@ActivityId) THROW 51266,N'Booking đã đăng ký hoạt động này.',1;
  SELECT @AccountId=AccountId FROM dbo.Accounts WITH(UPDLOCK,HOLDLOCK) WHERE BookingId=@BookingId AND Status='OPEN';
  IF @AccountId IS NULL THROW 51267,N'Tài khoản booking đã chốt hoặc chưa tồn tại.',1;
  SET @Price=@Fee;
  IF @IncludedServiceId IS NOT NULL AND EXISTS(SELECT 1 FROM dbo.PackageServices WHERE PackageId=@PackageId AND ServiceId=@IncludedServiceId) SET @Price=0;
  SET @RegistrationStatus=CASE WHEN (SELECT COUNT(*) FROM dbo.Registrations WHERE ActivityId=@ActivityId AND Status='CONFIRMED')>=@Capacity THEN 'WAITLIST' ELSE 'CONFIRMED' END;
  EXEC sys.sp_set_session_context @key=N'ActorId',@value=@ActorId;
  INSERT dbo.Registrations(ActivityId,BookingId,Status,PriceAtRegistration) VALUES(@ActivityId,@BookingId,@RegistrationStatus,@Price);
  DECLARE @RegistrationId int=SCOPE_IDENTITY();
  IF @RegistrationStatus='CONFIRMED' INSERT dbo.Transactions(AccountId,RegistrationId,Amount) VALUES(@AccountId,@RegistrationId,@Price);
  COMMIT;
  SELECT @RegistrationId AS RegistrationId,@RegistrationStatus AS Status,@Price AS PriceAtRegistration;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
