:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminSaveUser
 @ActorId int,
 @UserId int=0,
 @Name nvarchar(100),
 @Email varchar(150),
 @Active bit,
 @RoleCodes varchar(500),
 @PasswordHash varchar(200)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;

  IF NOT EXISTS(
   SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId
   WHERE ur.UserId=@ActorId AND r.Code='ADMIN'
  ) THROW 51280,N'Chỉ quản trị viên được thay đổi người dùng.',1;
  IF @Name IS NULL OR LEN(LTRIM(RTRIM(@Name)))=0 OR LEN(@Name)>100
   THROW 51281,N'Tên người dùng không hợp lệ.',1;
  IF @Email IS NULL OR LEN(@Email)>150 OR @Email NOT LIKE '%_@_%._%'
   THROW 51282,N'Email không hợp lệ.',1;
  IF @PasswordHash IS NOT NULL AND (LEN(@PasswordHash)<>161 OR CHARINDEX(':',@PasswordHash)<>33)
   THROW 51283,N'Mật khẩu băm không hợp lệ.',1;

  DECLARE @RequestedRoles table(Code varchar(30) PRIMARY KEY);
  INSERT @RequestedRoles(Code)
  SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(COALESCE(@RoleCodes,''),',')
  WHERE LEN(LTRIM(RTRIM(value)))>0;
  IF NOT EXISTS(SELECT 1 FROM @RequestedRoles)
   THROW 51284,N'Người dùng phải có ít nhất một vai trò.',1;
  IF EXISTS(SELECT 1 FROM @RequestedRoles rr LEFT JOIN dbo.Roles r ON r.Code=rr.Code WHERE r.RoleId IS NULL)
   THROW 51285,N'Vai trò không hợp lệ.',1;
  IF EXISTS(SELECT 1 FROM dbo.Users WHERE Email=@Email AND UserId<>@UserId)
   THROW 51286,N'Email đã được sử dụng.',1;

  IF @UserId=0
  BEGIN
   IF @PasswordHash IS NULL THROW 51287,N'Người dùng mới phải có mật khẩu.',1;
   INSERT dbo.Users(Name,Email,PasswordHash,Active)
   VALUES(LTRIM(RTRIM(@Name)),LOWER(LTRIM(RTRIM(@Email))),@PasswordHash,@Active);
   SET @UserId=SCOPE_IDENTITY();
  END
  ELSE
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.Users WITH(UPDLOCK,HOLDLOCK) WHERE UserId=@UserId)
    THROW 51288,N'Người dùng không tồn tại.',1;
   IF @UserId=@ActorId AND @Active=0
    THROW 51289,N'Không thể tự khóa tài khoản đang quản trị.',1;
   IF @UserId=@ActorId AND NOT EXISTS(SELECT 1 FROM @RequestedRoles WHERE Code='ADMIN')
    THROW 51290,N'Không thể tự gỡ quyền quản trị.',1;
   IF EXISTS(
    SELECT 1 FROM dbo.Users u JOIN dbo.UserRoles ur ON ur.UserId=u.UserId JOIN dbo.Roles r ON r.RoleId=ur.RoleId
    WHERE u.UserId=@UserId AND u.Active=1 AND r.Code='ADMIN'
   ) AND (@Active=0 OR NOT EXISTS(SELECT 1 FROM @RequestedRoles WHERE Code='ADMIN'))
   AND 1=(
    SELECT COUNT(DISTINCT u.UserId) FROM dbo.Users u JOIN dbo.UserRoles ur ON ur.UserId=u.UserId
    JOIN dbo.Roles r ON r.RoleId=ur.RoleId WHERE u.Active=1 AND r.Code='ADMIN'
   ) THROW 51291,N'Hệ thống phải còn ít nhất một quản trị viên hoạt động.',1;

   UPDATE dbo.Users SET Name=LTRIM(RTRIM(@Name)),Email=LOWER(LTRIM(RTRIM(@Email))),Active=@Active,
    PasswordHash=COALESCE(@PasswordHash,PasswordHash)
   WHERE UserId=@UserId;
  END

  EXEC sys.sp_set_session_context @key=N'ActorId',@value=@ActorId;
  DELETE ur FROM dbo.UserRoles ur WHERE ur.UserId=@UserId
   AND NOT EXISTS(SELECT 1 FROM @RequestedRoles rr JOIN dbo.Roles r ON r.Code=rr.Code WHERE r.RoleId=ur.RoleId);
  INSERT dbo.UserRoles(UserId,RoleId)
  SELECT @UserId,r.RoleId FROM @RequestedRoles rr JOIN dbo.Roles r ON r.Code=rr.Code
  WHERE NOT EXISTS(SELECT 1 FROM dbo.UserRoles ur WHERE ur.UserId=@UserId AND ur.RoleId=r.RoleId);

  IF EXISTS(SELECT 1 FROM @RequestedRoles WHERE Code='PASSENGER')
   AND NOT EXISTS(SELECT 1 FROM dbo.Passengers WHERE UserId=@UserId)
   INSERT dbo.Passengers(UserId) VALUES(@UserId);

  COMMIT;
  SELECT @UserId AS UserId;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
 END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminSaveCatalog
 @ActorId int,@Entity varchar(20),@Id int=0,@Name nvarchar(150),
 @ParentId int=NULL,@Number varchar(20)=NULL,@Capacity int=NULL,
 @Price decimal(18,2)=NULL,@Kind varchar(20)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@ActorId AND r.Code='ADMIN')
  THROW 51280,N'Chỉ quản trị viên được thay đổi danh mục.',1;
 IF @Entity NOT IN('ship','zone','cabin','port','provider','service','package','device')
  THROW 51292,N'Danh mục không được hỗ trợ.',1;
 IF @Entity<>'cabin' AND (@Name IS NULL OR LEN(LTRIM(RTRIM(@Name)))=0 OR LEN(@Name)>150)
  THROW 51293,N'Tên danh mục không hợp lệ.',1;
 BEGIN TRY
  BEGIN TRAN;
  IF @Entity='ship'
  BEGIN
   IF @Capacity IS NULL OR @Capacity<1 THROW 51294,N'Sức chứa tàu không hợp lệ.',1;
   IF @Id=0 INSERT dbo.Ships(Name,Capacity) VALUES(LTRIM(RTRIM(@Name)),@Capacity);
   ELSE UPDATE dbo.Ships SET Name=LTRIM(RTRIM(@Name)),Capacity=@Capacity WHERE ShipId=@Id;
  END
  ELSE IF @Entity='zone'
  BEGIN
   IF @Id=0 INSERT dbo.Zones(ShipId,Name) VALUES(@ParentId,LTRIM(RTRIM(@Name)));
   ELSE UPDATE dbo.Zones SET Name=LTRIM(RTRIM(@Name)) WHERE ZoneId=@Id;
  END
  ELSE IF @Entity='cabin'
  BEGIN
   IF @Number IS NULL OR LEN(LTRIM(RTRIM(@Number)))=0 OR LEN(@Number)>20 THROW 51295,N'Số cabin không hợp lệ.',1;
   IF @Id=0 INSERT dbo.Cabins(ShipId,Number) VALUES(@ParentId,LTRIM(RTRIM(@Number)));
   ELSE UPDATE dbo.Cabins SET Number=LTRIM(RTRIM(@Number)) WHERE CabinId=@Id;
  END
  ELSE IF @Entity='port'
  BEGIN IF @Id=0 INSERT dbo.Ports(Name) VALUES(LTRIM(RTRIM(@Name))); ELSE UPDATE dbo.Ports SET Name=LTRIM(RTRIM(@Name)) WHERE PortId=@Id; END
  ELSE IF @Entity='provider'
  BEGIN IF @Id=0 INSERT dbo.Providers(Name) VALUES(LTRIM(RTRIM(@Name))); ELSE UPDATE dbo.Providers SET Name=LTRIM(RTRIM(@Name)) WHERE ProviderId=@Id; END
  ELSE IF @Entity='service'
  BEGIN
   IF @Price IS NULL OR @Price<0 THROW 51296,N'Giá dịch vụ không hợp lệ.',1;
   IF @Id=0 INSERT dbo.Services(Name,Price) VALUES(LTRIM(RTRIM(@Name)),@Price);
   ELSE UPDATE dbo.Services SET Name=LTRIM(RTRIM(@Name)),Price=@Price WHERE ServiceId=@Id;
  END
  ELSE IF @Entity='package'
  BEGIN IF @Id=0 INSERT dbo.Packages(Name) VALUES(LTRIM(RTRIM(@Name))); ELSE UPDATE dbo.Packages SET Name=LTRIM(RTRIM(@Name)) WHERE PackageId=@Id; END
  ELSE IF @Entity='device'
  BEGIN
   IF @Kind NOT IN('POS','CHECKIN') THROW 51297,N'Loại thiết bị không hợp lệ.',1;
   IF @Id=0 INSERT dbo.Devices(Name,Kind) VALUES(LTRIM(RTRIM(@Name)),@Kind);
   ELSE UPDATE dbo.Devices SET Name=LTRIM(RTRIM(@Name)) WHERE DeviceId=@Id;
  END
  IF @Id<>0 AND @@ROWCOUNT=0 THROW 51298,N'Danh mục không tồn tại.',1;
  DECLARE @SavedId int=CASE WHEN @Id=0 THEN CONVERT(int,SCOPE_IDENTITY()) ELSE @Id END;
  INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId) VALUES(@Entity,@SavedId,CASE WHEN @Id=0 THEN 'INSERT' ELSE 'UPDATE' END,@ActorId);
  COMMIT; SELECT @SavedId AS Id;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminSaveBooking
 @ActorId int,@BookingId int=0,@CruiseId int,@UserId int,@CabinId int,@PackageId int
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@ActorId AND r.Code='ADMIN')
  THROW 51280,N'Chỉ quản trị viên được gán booking.',1;
 DECLARE @PassengerId int=(SELECT p.PassengerId FROM dbo.Passengers p JOIN dbo.Users u ON u.UserId=p.UserId
  JOIN dbo.UserRoles ur ON ur.UserId=u.UserId JOIN dbo.Roles r ON r.RoleId=ur.RoleId
  WHERE u.UserId=@UserId AND u.Active=1 AND r.Code='PASSENGER');
 IF @PassengerId IS NULL THROW 51310,N'Người dùng không phải hành khách đang hoạt động.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Cruises cr JOIN dbo.Cabins cb ON cb.ShipId=cr.ShipId WHERE cr.CruiseId=@CruiseId AND cb.CabinId=@CabinId)
  THROW 51311,N'Cabin không thuộc tàu của chuyến.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Packages WHERE PackageId=@PackageId) THROW 51312,N'Gói dịch vụ không tồn tại.',1;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @Action varchar(10)='UPDATE';
  IF @BookingId=0
  BEGIN
   INSERT dbo.Bookings(CruiseId,PassengerId,CabinId,PackageId) VALUES(@CruiseId,@PassengerId,@CabinId,@PackageId);
   SET @BookingId=SCOPE_IDENTITY();
   INSERT dbo.Accounts(BookingId) VALUES(@BookingId);
   SET @Action='INSERT';
  END
  ELSE
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.Bookings WITH(UPDLOCK,HOLDLOCK) WHERE BookingId=@BookingId AND CruiseId=@CruiseId AND PassengerId=@PassengerId)
    THROW 51313,N'Không được đổi hành khách hoặc chuyến của booking hiện có.',1;
   UPDATE dbo.Bookings SET CabinId=@CabinId,PackageId=@PackageId WHERE BookingId=@BookingId;
  END
  INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId) VALUES('Booking',@BookingId,@Action,@ActorId);
  COMMIT; SELECT @BookingId AS BookingId;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminPackageService
 @ActorId int,@PackageId int,@ServiceId int,@Included bit
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@ActorId AND r.Code='ADMIN')
  THROW 51280,N'Chỉ quản trị viên được cấu hình gói.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Packages WHERE PackageId=@PackageId) OR NOT EXISTS(SELECT 1 FROM dbo.Services WHERE ServiceId=@ServiceId)
  THROW 51314,N'Gói hoặc dịch vụ không tồn tại.',1;
 IF @Included=1 AND NOT EXISTS(SELECT 1 FROM dbo.PackageServices WHERE PackageId=@PackageId AND ServiceId=@ServiceId)
  INSERT dbo.PackageServices(PackageId,ServiceId) VALUES(@PackageId,@ServiceId);
 ELSE IF @Included=0 DELETE dbo.PackageServices WHERE PackageId=@PackageId AND ServiceId=@ServiceId;
 INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId) VALUES('PackageService',@PackageId,CASE WHEN @Included=1 THEN 'INSERT' ELSE 'DELETE' END,@ActorId);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminSavePolicy
 @ActorId int,@CancelHours int,@RefundPercent int
AS
BEGIN
 SET NOCOUNT ON;
 IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@ActorId AND r.Code='ADMIN')
  THROW 51280,N'Chỉ quản trị viên được sửa chính sách.',1;
 IF @CancelHours<0 OR @CancelHours>8760 OR @RefundPercent<0 OR @RefundPercent>100
  THROW 51315,N'Chính sách hủy hoặc hoàn phí không hợp lệ.',1;
 UPDATE dbo.Policy SET CancelHours=@CancelHours,RefundPercent=@RefundPercent WHERE PolicyId=1;
 INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId) VALUES('Policy',1,'UPDATE',@ActorId);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminSetIdentifierActive
 @ActorId int,@IdentifierId int,@Active bit
AS
BEGIN
 SET NOCOUNT ON;
 IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@ActorId AND r.Code='ADMIN')
  THROW 51280,N'Chỉ quản trị viên được đổi mã định danh.',1;
 UPDATE dbo.Identifiers SET Active=@Active WHERE IdentifierId=@IdentifierId;
 IF @@ROWCOUNT=0 THROW 51316,N'Mã định danh không tồn tại.',1;
 INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId) VALUES('Identifier',@IdentifierId,'UPDATE',@ActorId);
END;
GO
