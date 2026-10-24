:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
GO

-- QR/barcode được xác thực tại SQL Server; UNIQUE(CheckIns.RegistrationId)
-- là lớp bảo vệ cuối cùng nếu hai máy quét gửi cùng lúc.
CREATE OR ALTER PROCEDURE dbo.usp_CheckIn
 @ActivityId int,
 @Code varchar(100),
 @DeviceId int,
 @StaffId int
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @Kind varchar(20)=(SELECT Kind FROM dbo.Activities WHERE ActivityId=@ActivityId);
 DECLARE @RequiredRole varchar(30)=CASE WHEN @Kind='SHORE' THEN 'SHORE' ELSE 'ACTIVITY' END;
 IF @Kind IS NULL THROW 51500,N'Hoạt động không tồn tại.',1;
 EXEC dbo.usp_RequireRole @StaffId,@RequiredRole;
 IF NULLIF(LTRIM(RTRIM(@Code)),'') IS NULL THROW 51501,N'Mã hành khách không hợp lệ.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Devices WHERE DeviceId=@DeviceId AND Kind='CHECKIN')
  THROW 51502,N'Thiết bị không phải máy check-in.',1;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @RegistrationId int,@Passenger nvarchar(100),@Activity nvarchar(150),@CorrelationId uniqueidentifier=NEWID();
  SELECT @RegistrationId=r.RegistrationId,@Passenger=u.Name,@Activity=a.Name
  FROM dbo.Identifiers i WITH(UPDLOCK,HOLDLOCK)
  JOIN dbo.Bookings b ON b.BookingId=i.BookingId
  JOIN dbo.Passengers p ON p.PassengerId=b.PassengerId
  JOIN dbo.Users u ON u.UserId=p.UserId AND u.Active=1
  JOIN dbo.Registrations r WITH(UPDLOCK,HOLDLOCK) ON r.BookingId=b.BookingId AND r.ActivityId=@ActivityId
  JOIN dbo.Activities a ON a.ActivityId=r.ActivityId
  WHERE i.Code=LTRIM(RTRIM(@Code)) AND i.Active=1 AND r.Status='CONFIRMED' AND a.Status IN('OPEN','DELAYED');
  IF @RegistrationId IS NULL THROW 51503,N'Mã không hợp lệ, đã bị vô hiệu hoặc khách chưa đăng ký xác nhận.',1;
  IF EXISTS(SELECT 1 FROM dbo.CheckIns WITH(UPDLOCK,HOLDLOCK) WHERE RegistrationId=@RegistrationId)
   THROW 51504,N'Khách đã check-in cho hoạt động này.',1;
  EXEC sys.sp_set_session_context @key=N'ActorId',@value=@StaffId;
  EXEC sys.sp_set_session_context @key=N'CorrelationId',@value=@CorrelationId;
  INSERT dbo.CheckIns(RegistrationId,DeviceId,StaffId) VALUES(@RegistrationId,@DeviceId,@StaffId);
  DECLARE @CheckInId int=CONVERT(int,SCOPE_IDENTITY());
  INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId,Details,CorrelationId)
   VALUES('CheckIn',@CheckInId,'INSERT',@StaffId,CONCAT(N'Passenger=',@Passenger,N'; Activity=',@Activity,N'; Device=',@DeviceId),@CorrelationId);
  COMMIT;
  SELECT @RegistrationId AS RegistrationId,@CheckInId AS CheckInId;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
 END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ReturnToShip
 @RegistrationId int,
 @StaffId int
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 EXEC dbo.usp_RequireRole @StaffId,'SHORE';
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @CheckInId int,@Activity nvarchar(150),@CorrelationId uniqueidentifier=NEWID();
  SELECT @CheckInId=ci.CheckInId,@Activity=a.Name
  FROM dbo.CheckIns ci WITH(UPDLOCK,HOLDLOCK)
  JOIN dbo.Registrations r ON r.RegistrationId=ci.RegistrationId
  JOIN dbo.Activities a ON a.ActivityId=r.ActivityId
  WHERE ci.RegistrationId=@RegistrationId AND a.Kind='SHORE' AND r.Status='CONFIRMED' AND ci.ReturnedAt IS NULL;
  IF @CheckInId IS NULL THROW 51505,N'Khách chưa check-in tour bờ hoặc đã được ghi nhận về tàu.',1;
  EXEC sys.sp_set_session_context @key=N'ActorId',@value=@StaffId;
  EXEC sys.sp_set_session_context @key=N'CorrelationId',@value=@CorrelationId;
  UPDATE dbo.CheckIns SET ReturnedAt=SYSUTCDATETIME() WHERE CheckInId=@CheckInId AND ReturnedAt IS NULL;
  IF @@ROWCOUNT=0 THROW 51505,N'Khách đã được ghi nhận về tàu.',1;
  INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId,Details,CorrelationId)
   VALUES('CheckIn',@CheckInId,'RETURN',@StaffId,CONCAT(N'Activity=',@Activity,N'; Registration=',@RegistrationId),@CorrelationId);
  COMMIT;
  SELECT @RegistrationId AS RegistrationId,@CheckInId AS CheckInId;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
 END CATCH
END;
GO
