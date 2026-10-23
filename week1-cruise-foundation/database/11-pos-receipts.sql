:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.POSReceipts',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.POSReceipts(
  ReceiptId bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,
  ClientId uniqueidentifier NOT NULL UNIQUE REFERENCES dbo.Transactions(ClientId),
  DeviceId int NOT NULL REFERENCES dbo.Devices(DeviceId),
  StaffId int NOT NULL REFERENCES dbo.Users(UserId),
  SyncedAt datetime2(3) NOT NULL CONSTRAINT DF_POSReceipts_SyncedAt DEFAULT SYSUTCDATETIME()
 );
 CREATE INDEX IX_POSReceipts_Staff_SyncedAt ON dbo.POSReceipts(StaffId,SyncedAt DESC) INCLUDE(ClientId,DeviceId);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_SyncPOS
 @Code varchar(100),@ServiceId int,@Quantity int,@DeviceId int,@StaffId int,@ClientId uniqueidentifier
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  EXEC dbo.usp_PostPOS @Code=@Code,@ServiceId=@ServiceId,@Quantity=@Quantity,@DeviceId=@DeviceId,@StaffId=@StaffId,@ClientId=@ClientId;
  IF NOT EXISTS(SELECT 1 FROM dbo.POSReceipts WITH(UPDLOCK,HOLDLOCK) WHERE ClientId=@ClientId)
   INSERT dbo.POSReceipts(ClientId,DeviceId,StaffId) VALUES(@ClientId,@DeviceId,@StaffId);
  COMMIT;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
 END CATCH;
END;
GO
