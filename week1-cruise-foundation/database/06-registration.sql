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

IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Registrations') AND name='IX_Registrations_WaitlistOrder')
 CREATE INDEX IX_Registrations_WaitlistOrder
 ON dbo.Registrations(ActivityId,Status,CreatedAt,RegistrationId)
 INCLUDE(BookingId,PriceAtRegistration);
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

CREATE OR ALTER PROCEDURE dbo.usp_PromoteActivityWaitlist
 @ActivityId int,
 @ActorId int=NULL
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;

  DECLARE @Capacity int,@ActivityStatus varchar(20),@StartsAt datetime2,
          @Available int,@Promoted int=0,@RegistrationId int,@AccountId int,
          @Price decimal(18,2);

  SELECT @Capacity=a.Capacity,@ActivityStatus=a.Status,@StartsAt=a.StartsAt
  FROM dbo.Activities a WITH(UPDLOCK,HOLDLOCK)
  WHERE a.ActivityId=@ActivityId;

  IF @Capacity IS NULL THROW 51268,N'Hoạt động không tồn tại.',1;

  IF @ActivityStatus='OPEN' AND @StartsAt>SYSDATETIME()
  BEGIN
   SET @Available=@Capacity-(
    SELECT COUNT(*) FROM dbo.Registrations
    WHERE ActivityId=@ActivityId AND Status='CONFIRMED'
   );

   IF @ActorId IS NOT NULL
    EXEC sys.sp_set_session_context @key=N'ActorId',@value=@ActorId;

   WHILE @Available>0
   BEGIN
    SET @RegistrationId=NULL;
    SELECT TOP(1)
     @RegistrationId=r.RegistrationId,
     @AccountId=ac.AccountId,
     @Price=COALESCE(r.PriceAtRegistration,a.Fee)
    FROM dbo.Registrations r WITH(UPDLOCK,READPAST,ROWLOCK)
    JOIN dbo.Activities a ON a.ActivityId=r.ActivityId
    JOIN dbo.Accounts ac ON ac.BookingId=r.BookingId AND ac.Status='OPEN'
    WHERE r.ActivityId=@ActivityId AND r.Status='WAITLIST'
    ORDER BY r.CreatedAt,r.RegistrationId;

    IF @RegistrationId IS NULL BREAK;

    UPDATE dbo.Registrations
    SET Status='CONFIRMED',PriceAtRegistration=@Price
    WHERE RegistrationId=@RegistrationId AND Status='WAITLIST';

    IF @@ROWCOUNT=1
    BEGIN
     IF NOT EXISTS(SELECT 1 FROM dbo.Transactions WHERE RegistrationId=@RegistrationId)
      INSERT dbo.Transactions(AccountId,RegistrationId,Amount)
      VALUES(@AccountId,@RegistrationId,@Price);
     SET @Promoted+=1;
     SET @Available-=1;
    END
   END
  END

  COMMIT;
  SELECT @Promoted AS PromotedCount;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
 END CATCH
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_RegistrationWaitlistPromotion
ON dbo.Registrations AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @ActivityId int,@ActorId int=TRY_CONVERT(int,SESSION_CONTEXT(N'ActorId'));
 DECLARE activity_cursor CURSOR LOCAL FAST_FORWARD FOR
  SELECT DISTINCT d.ActivityId
  FROM deleted d
  LEFT JOIN inserted i ON i.RegistrationId=d.RegistrationId
  WHERE d.Status='CONFIRMED' AND (i.RegistrationId IS NULL OR i.Status<>'CONFIRMED');
 OPEN activity_cursor;
 FETCH NEXT FROM activity_cursor INTO @ActivityId;
 WHILE @@FETCH_STATUS=0
 BEGIN
  EXEC dbo.usp_PromoteActivityWaitlist @ActivityId=@ActivityId,@ActorId=@ActorId;
  FETCH NEXT FROM activity_cursor INTO @ActivityId;
 END
 CLOSE activity_cursor;
 DEALLOCATE activity_cursor;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_ActivityCapacityWaitlistPromotion
ON dbo.Activities AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF NOT UPDATE(Capacity) RETURN;
 DECLARE @ActivityId int,@ActorId int=TRY_CONVERT(int,SESSION_CONTEXT(N'ActorId'));
 DECLARE activity_cursor CURSOR LOCAL FAST_FORWARD FOR
  SELECT i.ActivityId
  FROM inserted i JOIN deleted d ON d.ActivityId=i.ActivityId
  WHERE i.Capacity>d.Capacity;
 OPEN activity_cursor;
 FETCH NEXT FROM activity_cursor INTO @ActivityId;
 WHILE @@FETCH_STATUS=0
 BEGIN
  EXEC dbo.usp_PromoteActivityWaitlist @ActivityId=@ActivityId,@ActorId=@ActorId;
  FETCH NEXT FROM activity_cursor INTO @ActivityId;
 END
 CLOSE activity_cursor;
 DEALLOCATE activity_cursor;
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
