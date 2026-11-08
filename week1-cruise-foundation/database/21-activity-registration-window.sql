:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
GO

IF COL_LENGTH('dbo.Activities','RegistrationOpenHours') IS NULL
 ALTER TABLE dbo.Activities ADD RegistrationOpenHours int NULL;
IF COL_LENGTH('dbo.Activities','RegistrationCloseHours') IS NULL
 ALTER TABLE dbo.Activities ADD RegistrationCloseHours int NULL;
IF NOT EXISTS(SELECT 1 FROM sys.check_constraints WHERE name='CK_Activities_RegistrationWindow')
 ALTER TABLE dbo.Activities ADD CONSTRAINT CK_Activities_RegistrationWindow CHECK(
  (RegistrationOpenHours IS NULL AND RegistrationCloseHours IS NULL) OR
  (RegistrationOpenHours BETWEEN 0 AND 8760 AND RegistrationCloseHours BETWEEN 0 AND 8760 AND RegistrationOpenHours>RegistrationCloseHours));
GO

CREATE OR ALTER PROCEDURE dbo.usp_SaveOnboardActivity
 @ActorId int,@ActivityId int=0,@CruiseId int,@ZoneId int,@Name nvarchar(150),
 @StartsAt datetime2,@EndsAt datetime2,@Capacity int,@Fee decimal(18,2),
 @Status varchar(20)='OPEN',@RegistrationOpenHours int=NULL,@RegistrationCloseHours int=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@ActorId AND r.Code IN('ACTIVITY','ADMIN'))
  THROW 51400,N'Chỉ quản lý hoạt động được thay đổi hoạt động trên tàu.',1;
 IF @Name IS NULL OR LEN(LTRIM(RTRIM(@Name)))=0 OR LEN(@Name)>150 THROW 51401,N'Tên hoạt động không hợp lệ.',1;
 IF @StartsAt IS NULL OR @EndsAt IS NULL OR @EndsAt<=@StartsAt THROW 51402,N'Thời gian kết thúc phải sau thời gian bắt đầu.',1;
 IF @Capacity<1 OR @Capacity>100000 THROW 51403,N'Sức chứa phải từ 1 đến 100000.',1;
 IF @Fee<0 OR @Fee>1000000000000 THROW 51404,N'Phí hoạt động không hợp lệ.',1;
 IF @Status NOT IN('OPEN','DELAYED','COMPLETED') THROW 51405,N'Trạng thái hoạt động không hợp lệ.',1;
 IF @Status='COMPLETED' AND @EndsAt>SYSDATETIME() THROW 51419,N'Chỉ đánh dấu hoàn thành sau khi hoạt động kết thúc.',1;
 IF (@RegistrationOpenHours IS NULL AND @RegistrationCloseHours IS NOT NULL) OR (@RegistrationOpenHours IS NOT NULL AND @RegistrationCloseHours IS NULL)
  THROW 51420,N'Cần nhập cả thời điểm mở và đóng đăng ký, hoặc để trống cả hai để dùng chính sách chung.',1;
 IF @RegistrationOpenHours IS NOT NULL AND (@RegistrationOpenHours<0 OR @RegistrationOpenHours>8760 OR @RegistrationCloseHours<0 OR @RegistrationCloseHours>8760 OR @RegistrationOpenHours<=@RegistrationCloseHours)
  THROW 51421,N'Khung giờ riêng không hợp lệ: giờ mở phải lớn hơn giờ đóng.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Cruises WHERE CruiseId=@CruiseId AND Status IN('OPEN','SAILING')) THROW 51406,N'Chuyến không tồn tại hoặc đã kết thúc.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Cruises c JOIN dbo.Zones z ON z.ShipId=c.ShipId WHERE c.CruiseId=@CruiseId AND z.ZoneId=@ZoneId) THROW 51407,N'Khu vực không thuộc tàu của chuyến.',1;
 IF EXISTS(SELECT 1 FROM dbo.Cruises WHERE CruiseId=@CruiseId AND (CAST(@StartsAt AS date)<StartDate OR CAST(@EndsAt AS date)>EndDate))
  THROW 51408,N'Thời gian hoạt động phải nằm trong ngày của chuyến.',1;
 BEGIN TRY
  BEGIN TRAN;
  IF @ActivityId=0
  BEGIN
   INSERT dbo.Activities(CruiseId,ZoneId,Name,Kind,StartsAt,EndsAt,Capacity,Fee,Status,RegistrationOpenHours,RegistrationCloseHours)
   VALUES(@CruiseId,@ZoneId,LTRIM(RTRIM(@Name)),'ONBOARD',@StartsAt,@EndsAt,@Capacity,@Fee,@Status,@RegistrationOpenHours,@RegistrationCloseHours);
   SET @ActivityId=CONVERT(int,SCOPE_IDENTITY());
   INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId,Details,CorrelationId)
   VALUES('Activity',@ActivityId,'INSERT',@ActorId,CONCAT(N'Name=',@Name,N'; Cruise=',@CruiseId,N'; Zone=',@ZoneId,N'; RegistrationWindow=',COALESCE(CONVERT(varchar(10),@RegistrationOpenHours),'GLOBAL'),N'/',COALESCE(CONVERT(varchar(10),@RegistrationCloseHours),'GLOBAL')),NEWID());
  END
  ELSE
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.Activities WITH(UPDLOCK,HOLDLOCK) WHERE ActivityId=@ActivityId AND Kind='ONBOARD' AND Status<>'CANCELLED') THROW 51409,N'Không tìm thấy hoạt động trên tàu có thể sửa.',1;
   IF EXISTS(SELECT 1 FROM dbo.Activities WHERE ActivityId=@ActivityId AND CruiseId<>@CruiseId AND EXISTS(SELECT 1 FROM dbo.Registrations WHERE ActivityId=@ActivityId)) THROW 51416,N'Không thể chuyển chuyến vì hoạt động đã có đăng ký.',1;
   IF EXISTS(SELECT 1 FROM dbo.Registrations WHERE ActivityId=@ActivityId AND Status='CONFIRMED' AND @Capacity<(SELECT COUNT(*) FROM dbo.Registrations WHERE ActivityId=@ActivityId AND Status='CONFIRMED')) THROW 51410,N'Sức chứa mới thấp hơn số lượt đã xác nhận.',1;
   UPDATE dbo.Activities SET CruiseId=@CruiseId,ZoneId=@ZoneId,Name=LTRIM(RTRIM(@Name)),StartsAt=@StartsAt,EndsAt=@EndsAt,Capacity=@Capacity,Fee=@Fee,Status=@Status,RegistrationOpenHours=@RegistrationOpenHours,RegistrationCloseHours=@RegistrationCloseHours
   WHERE ActivityId=@ActivityId AND Kind='ONBOARD';
   IF @@ROWCOUNT=0 THROW 51409,N'Không tìm thấy hoạt động trên tàu có thể sửa.',1;
   INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId,Details,CorrelationId)
   VALUES('Activity',@ActivityId,'UPDATE',@ActorId,CONCAT(N'Name=',@Name,N'; Cruise=',@CruiseId,N'; Zone=',@ZoneId,N'; Status=',@Status,N'; RegistrationWindow=',COALESCE(CONVERT(varchar(10),@RegistrationOpenHours),'GLOBAL'),N'/',COALESCE(CONVERT(varchar(10),@RegistrationCloseHours),'GLOBAL')),NEWID());
  END
  COMMIT; SELECT @ActivityId AS ActivityId;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Register
 @BookingId int,@ActivityId int,@ActorId int
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @CruiseId int,@Capacity int,@Fee decimal(18,2),@StartsAt datetime2,@ActivityStatus varchar(20),
   @IncludedServiceId int,@AccountId int,@PackageId int,@BookingCruiseId int,@Price decimal(18,2),
   @RegistrationStatus varchar(20),@OpenHours int,@CloseHours int,@Now datetime2=SYSDATETIME();
  SELECT @CruiseId=a.CruiseId,@Capacity=a.Capacity,@Fee=a.Fee,@StartsAt=a.StartsAt,@ActivityStatus=a.Status,
   @IncludedServiceId=a.IncludedServiceId,@OpenHours=COALESCE(a.RegistrationOpenHours,p.RegistrationOpenHours),
   @CloseHours=COALESCE(a.RegistrationCloseHours,p.RegistrationCloseHours)
  FROM dbo.Activities a WITH(UPDLOCK,HOLDLOCK) CROSS JOIN dbo.Policy p
  WHERE a.ActivityId=@ActivityId AND p.PolicyId=1;
  IF @CruiseId IS NULL THROW 51262,N'Hoạt động không tồn tại.',1;
  IF @ActivityStatus<>'OPEN' OR @Now<DATEADD(HOUR,-@OpenHours,@StartsAt) OR @Now>=DATEADD(HOUR,-@CloseHours,@StartsAt)
   THROW 51263,N'Hoạt động chưa mở đăng ký hoặc đã quá thời hạn đăng ký.',1;
  SELECT @BookingCruiseId=b.CruiseId,@PackageId=b.PackageId FROM dbo.Bookings b JOIN dbo.Cruises c ON c.CruiseId=b.CruiseId AND c.Status<>'CLOSED' WHERE b.BookingId=@BookingId;
  IF @BookingCruiseId IS NULL OR @BookingCruiseId<>@CruiseId THROW 51264,N'Booking không thuộc chuyến đang mở của hoạt động.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Bookings b JOIN dbo.Passengers p ON p.PassengerId=b.PassengerId WHERE b.BookingId=@BookingId AND p.UserId=@ActorId)
   AND NOT EXISTS(SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@ActorId AND r.Code='ADMIN') THROW 51265,N'Không có quyền đăng ký cho booking này.',1;
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
  COMMIT; SELECT @RegistrationId AS RegistrationId,@RegistrationStatus AS Status,@Price AS PriceAtRegistration;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
