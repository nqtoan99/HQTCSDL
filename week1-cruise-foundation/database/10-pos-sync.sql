:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
GO

-- SQL Server coi nhiều NULL là trùng trong UNIQUE constraint. POS không có đăng ký,
-- vì vậy chỉ cần duy nhất RegistrationId khi giá trị này khác NULL.
DECLARE @RegistrationConstraint sysname;
DECLARE @DropRegistrationConstraint nvarchar(max);
SELECT @RegistrationConstraint=kc.name
FROM sys.key_constraints kc
JOIN sys.index_columns ic ON ic.object_id=kc.parent_object_id AND ic.index_id=kc.unique_index_id
JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
WHERE kc.parent_object_id=OBJECT_ID(N'dbo.Transactions') AND kc.type='UQ'
GROUP BY kc.name
HAVING COUNT(*)=1 AND MAX(c.name)=N'RegistrationId';
IF @RegistrationConstraint IS NOT NULL
BEGIN
 SET @DropRegistrationConstraint=N'ALTER TABLE dbo.Transactions DROP CONSTRAINT '+QUOTENAME(@RegistrationConstraint)+N';';
 EXEC(@DropRegistrationConstraint);
END;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.Transactions') AND name=N'UX_Transactions_RegistrationId')
 CREATE UNIQUE INDEX UX_Transactions_RegistrationId ON dbo.Transactions(RegistrationId) WHERE RegistrationId IS NOT NULL;
GO

CREATE OR ALTER PROCEDURE dbo.usp_PostPOS
 @Code varchar(100),@ServiceId int,@Quantity int,@DeviceId int,@StaffId int,@ClientId uniqueidentifier
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 EXEC dbo.usp_RequireRole @StaffId,'POS';
 IF @ClientId IS NULL THROW 51400,N'Mã đồng bộ không hợp lệ.',1;
 IF NULLIF(TRIM(@Code),'') IS NULL OR @ServiceId<1 OR @DeviceId<1 THROW 51401,N'Thông tin giao dịch POS không hợp lệ.',1;
 IF @Quantity<1 OR @Quantity>100 THROW 51402,N'Số lượng phải từ 1 đến 100.',1;

 BEGIN TRY
  BEGIN TRAN;
  DECLARE @TransactionId int,@AccountId int,@PackageId int,@Price decimal(18,2);

  DECLARE @LockResult int,@LockResource nvarchar(255)=N'AuroraPOS:'+CONVERT(nvarchar(36),@ClientId);
  EXEC @LockResult=sys.sp_getapplock @Resource=@LockResource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
  IF @LockResult<0 THROW 51408,N'Giao dịch đang được đồng bộ. Hãy thử lại.',1;

  -- Khóa theo UUID; UNIQUE(ClientId) là lớp bảo vệ cuối cùng trước hai request đồng thời.
  SELECT @TransactionId=TransactionId
   FROM dbo.Transactions WITH(UPDLOCK,HOLDLOCK)
   WHERE ClientId=@ClientId;

  -- Retry được chấp nhận nếu mã khách đã bị vô hiệu sau lần ghi đầu; giao dịch mới thì không.
  SELECT @AccountId=a.AccountId,@PackageId=b.PackageId
   FROM dbo.Identifiers i WITH(UPDLOCK,HOLDLOCK)
   JOIN dbo.Bookings b ON b.BookingId=i.BookingId
   JOIN dbo.Accounts a WITH(UPDLOCK,HOLDLOCK) ON a.BookingId=b.BookingId
   WHERE i.Code=@Code AND (@TransactionId IS NOT NULL OR i.Active=1);
  IF @AccountId IS NULL THROW 51403,N'Mã hành khách không hợp lệ hoặc đã bị vô hiệu.',1;

  IF @TransactionId IS NOT NULL
  BEGIN
   IF NOT EXISTS(
    SELECT 1 FROM dbo.Transactions
    WHERE TransactionId=@TransactionId AND AccountId=@AccountId AND ServiceId=@ServiceId
      AND Quantity=@Quantity AND DeviceId=@DeviceId AND StaffId=@StaffId
   ) THROW 51404,N'UUID đã được dùng cho một nội dung giao dịch khác.',1;
   COMMIT;
   RETURN;
  END;

  IF NOT EXISTS(SELECT 1 FROM dbo.Accounts WHERE AccountId=@AccountId AND Status='OPEN')
   THROW 51405,N'Tài khoản đã chốt, không thể ghi thêm dịch vụ.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Devices WHERE DeviceId=@DeviceId AND Kind='POS')
   THROW 51406,N'Thiết bị được chọn không phải máy POS.',1;
  SELECT @Price=Price FROM dbo.Services WHERE ServiceId=@ServiceId;
  IF @Price IS NULL THROW 51407,N'Dịch vụ không tồn tại.',1;
  IF EXISTS(SELECT 1 FROM dbo.PackageServices WHERE PackageId=@PackageId AND ServiceId=@ServiceId) SET @Price=0;

  EXEC sys.sp_set_session_context @key=N'ActorId',@value=@StaffId;
  EXEC sys.sp_set_session_context @key=N'CorrelationId',@value=@ClientId;
  INSERT dbo.Transactions(AccountId,ServiceId,Quantity,DeviceId,StaffId,ClientId,Amount)
   VALUES(@AccountId,@ServiceId,@Quantity,@DeviceId,@StaffId,@ClientId,@Price*@Quantity);
  COMMIT;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
 END CATCH
END;
GO
