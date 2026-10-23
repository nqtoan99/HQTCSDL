:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
GO

IF COL_LENGTH('dbo.Activities','IncludedServiceId') IS NULL
 ALTER TABLE dbo.Activities ADD IncludedServiceId int NULL REFERENCES dbo.Services(ServiceId);
IF COL_LENGTH('dbo.Registrations','PriceAtRegistration') IS NULL
 ALTER TABLE dbo.Registrations ADD PriceAtRegistration decimal(18,2) NULL;
GO

-- Dữ liệu mẫu: gói Premium bao gồm hoạt động Đêm nhạc thông qua dịch vụ Nước uống.
UPDATE a SET IncludedServiceId=s.ServiceId
FROM dbo.Activities a
JOIN dbo.Services s ON s.Name=N'Nước uống'
WHERE a.Name=N'Đêm nhạc trên biển' AND a.IncludedServiceId IS NULL;
GO

IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE name='CK_Registrations_PriceAtRegistration')
 ALTER TABLE dbo.Registrations ADD CONSTRAINT CK_Registrations_PriceAtRegistration CHECK(PriceAtRegistration IS NULL OR PriceAtRegistration>=0);
GO

CREATE OR ALTER TRIGGER dbo.tr_RegistrationConsistency ON dbo.Registrations AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(
  SELECT 1 FROM inserted r
  JOIN dbo.Activities a ON a.ActivityId=r.ActivityId
  JOIN dbo.Bookings b ON b.BookingId=r.BookingId
  WHERE a.CruiseId<>b.CruiseId
 ) THROW 51260,N'Đăng ký phải thuộc đúng chuyến của hành khách.',1;
 IF EXISTS(
  SELECT 1 FROM dbo.Activities a
  JOIN (SELECT DISTINCT ActivityId FROM inserted) i ON i.ActivityId=a.ActivityId
  WHERE (SELECT COUNT(*) FROM dbo.Registrations r WHERE r.ActivityId=a.ActivityId AND r.Status='CONFIRMED')>a.Capacity
 ) THROW 51261,N'Hoạt động đã vượt quá sức chứa.',1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Register
 @BookingId int,
 @ActivityId int,
 @ActorId int
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;

  DECLARE @CruiseId int,@Capacity int,@Fee decimal(18,2),@StartsAt datetime2,
          @ActivityStatus varchar(20),@IncludedServiceId int,@AccountId int,
          @PackageId int,@BookingCruiseId int,@Price decimal(18,2),@RegistrationStatus varchar(20);

  SELECT @CruiseId=a.CruiseId,@Capacity=a.Capacity,@Fee=a.Fee,@StartsAt=a.StartsAt,
         @ActivityStatus=a.Status,@IncludedServiceId=a.IncludedServiceId
  FROM dbo.Activities a WITH(UPDLOCK,HOLDLOCK)
  WHERE a.ActivityId=@ActivityId;

  IF @CruiseId IS NULL THROW 51262,N'Hoạt động không tồn tại.',1;
  IF @ActivityStatus<>'OPEN' OR @StartsAt<=SYSDATETIME()
   THROW 51263,N'Hoạt động đã đóng hoặc đã bắt đầu.',1;

  SELECT @BookingCruiseId=b.CruiseId,@PackageId=b.PackageId
  FROM dbo.Bookings b
  JOIN dbo.Cruises c ON c.CruiseId=b.CruiseId AND c.Status<>'CLOSED'
  WHERE b.BookingId=@BookingId;

  IF @BookingCruiseId IS NULL OR @BookingCruiseId<>@CruiseId
   THROW 51264,N'Booking không thuộc chuyến đang mở của hoạt động.',1;

  IF NOT EXISTS(
   SELECT 1 FROM dbo.Bookings b
   JOIN dbo.Passengers p ON p.PassengerId=b.PassengerId
   WHERE b.BookingId=@BookingId AND p.UserId=@ActorId
  ) AND NOT EXISTS(
   SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId
   WHERE ur.UserId=@ActorId AND r.Code='ADMIN'
  ) THROW 51265,N'Không có quyền đăng ký cho booking này.',1;

  IF EXISTS(SELECT 1 FROM dbo.Registrations WHERE BookingId=@BookingId AND ActivityId=@ActivityId)
   THROW 51266,N'Booking đã đăng ký hoạt động này.',1;

  SELECT @AccountId=AccountId FROM dbo.Accounts WITH(UPDLOCK,HOLDLOCK)
  WHERE BookingId=@BookingId AND Status='OPEN';
  IF @AccountId IS NULL THROW 51267,N'Tài khoản booking đã chốt hoặc chưa tồn tại.',1;

  SET @Price=@Fee;
  IF @IncludedServiceId IS NOT NULL AND EXISTS(
   SELECT 1 FROM dbo.PackageServices
   WHERE PackageId=@PackageId AND ServiceId=@IncludedServiceId
  ) SET @Price=0;

  SET @RegistrationStatus=CASE WHEN (
   SELECT COUNT(*) FROM dbo.Registrations
   WHERE ActivityId=@ActivityId AND Status='CONFIRMED'
  )>=@Capacity THEN 'WAITLIST' ELSE 'CONFIRMED' END;

  EXEC sys.sp_set_session_context @key=N'ActorId',@value=@ActorId;
  INSERT dbo.Registrations(ActivityId,BookingId,Status,PriceAtRegistration)
  VALUES(@ActivityId,@BookingId,@RegistrationStatus,@Price);
  DECLARE @RegistrationId int=SCOPE_IDENTITY();

  IF @RegistrationStatus='CONFIRMED'
   INSERT dbo.Transactions(AccountId,RegistrationId,Amount)
   VALUES(@AccountId,@RegistrationId,@Price);

  COMMIT;
  SELECT @RegistrationId AS RegistrationId,@RegistrationStatus AS Status,@Price AS PriceAtRegistration;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
 END CATCH
END;
GO
