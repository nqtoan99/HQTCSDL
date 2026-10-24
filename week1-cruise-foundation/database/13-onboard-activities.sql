:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_SaveOnboardActivity
 @ActorId int,
 @ActivityId int=0,
 @CruiseId int,
 @ZoneId int,
 @Name nvarchar(150),
 @StartsAt datetime2,
 @EndsAt datetime2,
 @Capacity int,
 @Fee decimal(18,2),
 @Status varchar(20)='OPEN'
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@ActorId AND r.Code IN('ACTIVITY','ADMIN'))
  THROW 51400,N'Chỉ quản lý hoạt động được thay đổi hoạt động trên tàu.',1;
 IF @Name IS NULL OR LEN(LTRIM(RTRIM(@Name)))=0 OR LEN(@Name)>150
  THROW 51401,N'Tên hoạt động không hợp lệ.',1;
 IF @StartsAt IS NULL OR @EndsAt IS NULL OR @EndsAt<=@StartsAt
  THROW 51402,N'Thời gian kết thúc phải sau thời gian bắt đầu.',1;
 IF @Capacity<1 OR @Capacity>100000 THROW 51403,N'Sức chứa phải từ 1 đến 100000.',1;
 IF @Fee<0 OR @Fee>1000000000000 THROW 51404,N'Phí hoạt động không hợp lệ.',1;
 IF @Status NOT IN('OPEN','DELAYED','COMPLETED') THROW 51405,N'Trạng thái hoạt động không hợp lệ.',1;
 IF @Status='COMPLETED' AND @EndsAt>SYSDATETIME() THROW 51419,N'Chỉ đánh dấu hoàn thành sau khi hoạt động kết thúc.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Cruises WHERE CruiseId=@CruiseId AND Status IN('OPEN','SAILING'))
  THROW 51406,N'Chuyến không tồn tại hoặc đã kết thúc.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Cruises c JOIN dbo.Zones z ON z.ShipId=c.ShipId WHERE c.CruiseId=@CruiseId AND z.ZoneId=@ZoneId)
  THROW 51407,N'Khu vực không thuộc tàu của chuyến.',1;
 IF EXISTS(SELECT 1 FROM dbo.Cruises WHERE CruiseId=@CruiseId AND (CAST(@StartsAt AS date)<StartDate OR CAST(@EndsAt AS date)>EndDate))
  THROW 51408,N'Thời gian hoạt động phải nằm trong ngày của chuyến.',1;
 BEGIN TRY
  BEGIN TRAN;
  IF @ActivityId=0
  BEGIN
   INSERT dbo.Activities(CruiseId,ZoneId,Name,Kind,StartsAt,EndsAt,Capacity,Fee,Status)
   VALUES(@CruiseId,@ZoneId,LTRIM(RTRIM(@Name)),'ONBOARD',@StartsAt,@EndsAt,@Capacity,@Fee,@Status);
   SET @ActivityId=CONVERT(int,SCOPE_IDENTITY());
   INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId,Details,CorrelationId)
   VALUES('Activity',@ActivityId,'INSERT',@ActorId,CONCAT(N'Name=',@Name,N'; Cruise=',@CruiseId,N'; Zone=',@ZoneId),NEWID());
  END
  ELSE
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.Activities WITH(UPDLOCK,HOLDLOCK) WHERE ActivityId=@ActivityId AND Kind='ONBOARD' AND Status<>'CANCELLED')
    THROW 51409,N'Không tìm thấy hoạt động trên tàu có thể sửa.',1;
   IF EXISTS(SELECT 1 FROM dbo.Activities WHERE ActivityId=@ActivityId AND CruiseId<>@CruiseId AND EXISTS(SELECT 1 FROM dbo.Registrations WHERE ActivityId=@ActivityId))
    THROW 51416,N'Không thể chuyển chuyến vì hoạt động đã có đăng ký.',1;
   IF EXISTS(SELECT 1 FROM dbo.Registrations WHERE ActivityId=@ActivityId AND Status='CONFIRMED' AND @Capacity<(SELECT COUNT(*) FROM dbo.Registrations WHERE ActivityId=@ActivityId AND Status='CONFIRMED'))
    THROW 51410,N'Sức chứa mới thấp hơn số lượt đã xác nhận.',1;
   UPDATE dbo.Activities SET CruiseId=@CruiseId,ZoneId=@ZoneId,Name=LTRIM(RTRIM(@Name)),StartsAt=@StartsAt,EndsAt=@EndsAt,Capacity=@Capacity,Fee=@Fee,Status=@Status
   WHERE ActivityId=@ActivityId AND Kind='ONBOARD';
   IF @@ROWCOUNT=0 THROW 51409,N'Không tìm thấy hoạt động trên tàu có thể sửa.',1;
   INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId,Details,CorrelationId)
   VALUES('Activity',@ActivityId,'UPDATE',@ActorId,CONCAT(N'Name=',@Name,N'; Cruise=',@CruiseId,N'; Zone=',@ZoneId,N'; Status=',@Status),NEWID());
  END
  COMMIT; SELECT @ActivityId AS ActivityId;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CancelOnboardActivity
 @ActorId int,
 @ActivityId int,
 @Reason nvarchar(500)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@ActorId AND r.Code IN('ACTIVITY','ADMIN'))
  THROW 51400,N'Chỉ quản lý hoạt động được hủy hoạt động trên tàu.',1;
 IF @Reason IS NULL OR LEN(LTRIM(RTRIM(@Reason)))<3 OR LEN(@Reason)>500
  THROW 51411,N'Lý do hủy phải có từ 3 đến 500 ký tự.',1;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @Status varchar(20),@StartsAt datetime2,@RefundPercent int,@RefundTotal decimal(18,2)=0,@Count int=0;
  SELECT @Status=a.Status,@StartsAt=a.StartsAt,@RefundPercent=p.RefundPercent
  FROM dbo.Activities a WITH(UPDLOCK,HOLDLOCK) CROSS JOIN dbo.Policy p
  WHERE a.ActivityId=@ActivityId AND a.Kind='ONBOARD' AND p.PolicyId=1;
  IF @Status IS NULL THROW 51412,N'Không tìm thấy hoạt động trên tàu.',1;
  IF @Status='CANCELLED' THROW 51413,N'Hoạt động đã được hủy.',1;
  IF @Status='COMPLETED' OR @StartsAt<=SYSDATETIME() THROW 51414,N'Chỉ có thể hủy hoạt động chưa bắt đầu.',1;
  IF EXISTS(SELECT 1 FROM dbo.CheckIns ci JOIN dbo.Registrations r ON r.RegistrationId=ci.RegistrationId WHERE r.ActivityId=@ActivityId)
   THROW 51415,N'Không thể hủy vì đã có hành khách check-in.',1;
  IF EXISTS(SELECT 1 FROM dbo.Registrations r JOIN dbo.Accounts ac ON ac.BookingId=r.BookingId WHERE r.ActivityId=@ActivityId AND r.Status='CONFIRMED' AND ac.Status<>'OPEN')
   THROW 51417,N'Có tài khoản booking đã chốt; không thể hoàn phí hoạt động.',1;
  IF EXISTS(SELECT 1 FROM dbo.Registrations r LEFT JOIN dbo.Transactions t ON t.RegistrationId=r.RegistrationId AND t.Status='POSTED' WHERE r.ActivityId=@ActivityId AND r.Status='CONFIRMED' AND t.TransactionId IS NULL)
   THROW 51418,N'Thiếu giao dịch cho đăng ký đã xác nhận; cần đối soát trước khi hủy.',1;
  EXEC sys.sp_set_session_context @key=N'ActorId',@value=@ActorId;
  UPDATE dbo.Activities SET Status='CANCELLED' WHERE ActivityId=@ActivityId;
  DECLARE @Refunds table(RegistrationId int PRIMARY KEY,RefundAmount decimal(18,2));
  UPDATE t SET Status='REFUNDED',RefundAmount=ROUND(t.Amount*@RefundPercent/100.0,2),RefundedAt=SYSUTCDATETIME(),RefundedBy=@ActorId
   OUTPUT r.RegistrationId,inserted.RefundAmount INTO @Refunds
  FROM dbo.Transactions t JOIN dbo.Registrations r ON r.RegistrationId=t.RegistrationId
  WHERE r.ActivityId=@ActivityId AND r.Status='CONFIRMED' AND t.Status='POSTED';
  SELECT @RefundTotal=COALESCE(SUM(RefundAmount),0),@Count=COUNT(*) FROM @Refunds;
  UPDATE r SET Status='CANCELLED',CancelledAt=SYSUTCDATETIME(),CancelledBy=@ActorId,
   CancelReason=LTRIM(RTRIM(@Reason)),RefundAmount=CASE WHEN r.Status='CONFIRMED' THEN COALESCE((SELECT x.RefundAmount FROM @Refunds x WHERE x.RegistrationId=r.RegistrationId),0) ELSE 0 END
  FROM dbo.Registrations r WHERE r.ActivityId=@ActivityId AND r.Status IN('CONFIRMED','WAITLIST');
  INSERT dbo.AuditLog(Entity,EntityId,Action,ActorId,Details,CorrelationId)
  VALUES('Activity',@ActivityId,'CANCEL',@ActorId,CONCAT(N'Reason=',LTRIM(RTRIM(@Reason)),N'; RefundPercent=',@RefundPercent,N'; RefundTotal=',@RefundTotal),NEWID());
  COMMIT; SELECT (SELECT @ActivityId AS ActivityId,@Count AS RefundedTransactions,@RefundTotal AS RefundTotal,@RefundPercent AS RefundPercent FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS [json];
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
