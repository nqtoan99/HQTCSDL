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
