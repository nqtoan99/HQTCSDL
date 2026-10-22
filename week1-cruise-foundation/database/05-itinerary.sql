:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
GO

IF COL_LENGTH('dbo.ItineraryChanges','OldPortId') IS NULL
 ALTER TABLE dbo.ItineraryChanges ADD OldPortId int NULL;
IF COL_LENGTH('dbo.ItineraryChanges','NewPortId') IS NULL
 ALTER TABLE dbo.ItineraryChanges ADD NewPortId int NULL;
IF COL_LENGTH('dbo.ItineraryChanges','ChangeType') IS NULL
 ALTER TABLE dbo.ItineraryChanges ADD ChangeType varchar(10) NOT NULL CONSTRAINT DF_ItineraryChanges_ChangeType DEFAULT('UPDATE') WITH VALUES;
GO
IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE name='FK_ItineraryChanges_OldPort')
 ALTER TABLE dbo.ItineraryChanges ADD CONSTRAINT FK_ItineraryChanges_OldPort FOREIGN KEY(OldPortId) REFERENCES dbo.Ports(PortId);
IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE name='FK_ItineraryChanges_NewPort')
 ALTER TABLE dbo.ItineraryChanges ADD CONSTRAINT FK_ItineraryChanges_NewPort FOREIGN KEY(NewPortId) REFERENCES dbo.Ports(PortId);
GO
IF OBJECT_ID('dbo.CruiseChanges','U') IS NULL
BEGIN
 CREATE TABLE dbo.CruiseChanges(
  ChangeId bigint IDENTITY PRIMARY KEY,
  CruiseId int NOT NULL REFERENCES dbo.Cruises(CruiseId),
  ChangeType varchar(10) NOT NULL CHECK(ChangeType IN('CREATE','UPDATE')),
  OldShipId int NULL REFERENCES dbo.Ships(ShipId),
  NewShipId int NOT NULL REFERENCES dbo.Ships(ShipId),
  OldName nvarchar(150) NULL,
  NewName nvarchar(150) NOT NULL,
  OldStartDate date NULL,
  OldEndDate date NULL,
  NewStartDate date NOT NULL,
  NewEndDate date NOT NULL,
  OldStatus varchar(20) NULL,
  NewStatus varchar(20) NOT NULL,
  Reason nvarchar(500) NOT NULL,
  StaffId int NOT NULL REFERENCES dbo.Users(UserId),
  CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME()
 );
 CREATE INDEX IX_CruiseChanges_CruiseCreated ON dbo.CruiseChanges(CruiseId,CreatedAt DESC);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RequireRole @StaffId int,@Role varchar(30) AS
BEGIN
 SET NOCOUNT ON;
 IF NOT EXISTS(SELECT 1 FROM dbo.UserRoles ur JOIN dbo.Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=@StaffId AND r.Code IN(@Role,'ADMIN'))
  THROW 51001,N'Không có quyền cập nhật chuyến và lịch trình.',1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_SaveCruise
 @CruiseId int,@ShipId int,@Name nvarchar(150),@StartDate date,@EndDate date,@Status varchar(20),@Reason nvarchar(500),@StaffId int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 EXEC dbo.usp_RequireRole @StaffId,'ITINERARY';
 IF @ShipId<1 OR NOT EXISTS(SELECT 1 FROM dbo.Ships WHERE ShipId=@ShipId) THROW 51040,N'Tàu được chọn không tồn tại.',1;
 IF NULLIF(TRIM(@Name),N'') IS NULL OR @StartDate IS NULL OR @EndDate IS NULL OR @EndDate<@StartDate THROW 51041,N'Tên hoặc khoảng ngày chuyến đi không hợp lệ.',1;
 IF @Status NOT IN('OPEN','SAILING','CLOSED') THROW 51042,N'Trạng thái chuyến đi không hợp lệ.',1;
 IF NULLIF(TRIM(@Reason),N'') IS NULL THROW 51043,N'Cần ghi lý do hoặc mô tả thay đổi.',1;
 BEGIN TRY
  BEGIN TRAN;
  IF @CruiseId=0
  BEGIN
   INSERT dbo.Cruises(ShipId,Name,StartDate,EndDate,Status) VALUES(@ShipId,TRIM(@Name),@StartDate,@EndDate,@Status);
   SET @CruiseId=SCOPE_IDENTITY();
   INSERT dbo.CruiseChanges(CruiseId,ChangeType,NewShipId,NewName,NewStartDate,NewEndDate,NewStatus,Reason,StaffId)
    VALUES(@CruiseId,'CREATE',@ShipId,TRIM(@Name),@StartDate,@EndDate,@Status,TRIM(@Reason),@StaffId);
   INSERT dbo.Notifications(CruiseId,Message) VALUES(@CruiseId,LEFT(CONCAT(N'Lịch trình mới: ',TRIM(@Name),N'. ',TRIM(@Reason)),500));
  END
  ELSE
  BEGIN
   DECLARE @OldShipId int,@OldName nvarchar(150),@OldStartDate date,@OldEndDate date,@OldStatus varchar(20);
   SELECT @OldShipId=ShipId,@OldName=Name,@OldStartDate=StartDate,@OldEndDate=EndDate,@OldStatus=Status
    FROM dbo.Cruises WITH(UPDLOCK,HOLDLOCK) WHERE CruiseId=@CruiseId;
   IF @OldShipId IS NULL THROW 51044,N'Chuyến đi không tồn tại.',1;
   IF EXISTS(SELECT 1 FROM dbo.Stops WHERE CruiseId=@CruiseId AND (CAST(Arrival AS date)<@StartDate OR CAST(Departure AS date)>@EndDate))
    THROW 51045,N'Khoảng ngày mới không bao phủ toàn bộ điểm dừng hiện có.',1;
   IF EXISTS(SELECT 1 FROM dbo.Activities WHERE CruiseId=@CruiseId AND Status<>'CANCELLED' AND (CAST(StartsAt AS date)<@StartDate OR CAST(COALESCE(ReturnAt,EndsAt) AS date)>@EndDate))
    THROW 51046,N'Khoảng ngày mới không bao phủ toàn bộ hoạt động hiện có.',1;
   IF EXISTS(SELECT 1 FROM dbo.Bookings b JOIN dbo.Cabins cb ON cb.CabinId=b.CabinId WHERE b.CruiseId=@CruiseId AND cb.ShipId<>@ShipId)
    THROW 51047,N'Tàu mới không khớp với cabin của booking hiện có.',1;
   IF EXISTS(SELECT 1 FROM dbo.Activities a JOIN dbo.Zones z ON z.ZoneId=a.ZoneId WHERE a.CruiseId=@CruiseId AND z.ShipId<>@ShipId)
    THROW 51048,N'Tàu mới không khớp với khu vực hoạt động hiện có.',1;
   UPDATE dbo.Cruises SET ShipId=@ShipId,Name=TRIM(@Name),StartDate=@StartDate,EndDate=@EndDate,Status=@Status WHERE CruiseId=@CruiseId;
   IF @OldShipId<>@ShipId OR @OldName<>TRIM(@Name) OR @OldStartDate<>@StartDate OR @OldEndDate<>@EndDate OR @OldStatus<>@Status
   BEGIN
    INSERT dbo.CruiseChanges(CruiseId,ChangeType,OldShipId,NewShipId,OldName,NewName,OldStartDate,OldEndDate,NewStartDate,NewEndDate,OldStatus,NewStatus,Reason,StaffId)
     VALUES(@CruiseId,'UPDATE',@OldShipId,@ShipId,@OldName,TRIM(@Name),@OldStartDate,@OldEndDate,@StartDate,@EndDate,@OldStatus,@Status,TRIM(@Reason),@StaffId);
    INSERT dbo.Notifications(CruiseId,Message) VALUES(@CruiseId,LEFT(CONCAT(N'Thông tin chuyến ',TRIM(@Name),N' đã thay đổi. ',TRIM(@Reason)),500));
   END
  END;
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AddStop
 @CruiseId int,@PortId int,@Arrival datetime2,@Departure datetime2,@Reason nvarchar(500),@StaffId int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 EXEC dbo.usp_RequireRole @StaffId,'ITINERARY';
 IF @Departure<=@Arrival THROW 51050,N'Giờ rời cảng phải sau giờ đến.',1;
 IF NULLIF(TRIM(@Reason),N'') IS NULL THROW 51051,N'Cần ghi lý do thêm điểm dừng.',1;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @StartDate date,@EndDate date,@PortName nvarchar(100);
  SELECT @StartDate=StartDate,@EndDate=EndDate FROM dbo.Cruises WITH(UPDLOCK,HOLDLOCK) WHERE CruiseId=@CruiseId;
  SELECT @PortName=Name FROM dbo.Ports WHERE PortId=@PortId;
  IF @StartDate IS NULL OR @PortName IS NULL THROW 51052,N'Chuyến đi hoặc cảng không tồn tại.',1;
  IF CAST(@Arrival AS date)<@StartDate OR CAST(@Departure AS date)>@EndDate THROW 51053,N'Thời gian điểm dừng phải nằm trong ngày của chuyến.',1;
  IF EXISTS(SELECT 1 FROM dbo.Stops WITH(UPDLOCK,HOLDLOCK) WHERE CruiseId=@CruiseId AND Arrival<@Departure AND Departure>@Arrival)
   THROW 51054,N'Thời gian điểm dừng bị chồng với một cảng khác.',1;
  INSERT dbo.Stops(CruiseId,PortId,Arrival,Departure) VALUES(@CruiseId,@PortId,@Arrival,@Departure);
  DECLARE @StopId int=SCOPE_IDENTITY();
  INSERT dbo.ItineraryChanges(StopId,OldArrival,OldDeparture,NewArrival,NewDeparture,Reason,StaffId,OldPortId,NewPortId,ChangeType)
   VALUES(@StopId,@Arrival,@Departure,@Arrival,@Departure,TRIM(@Reason),@StaffId,NULL,@PortId,'CREATE');
  INSERT dbo.Notifications(CruiseId,Message) VALUES(@CruiseId,LEFT(CONCAT(N'Đã thêm điểm dừng ',@PortName,N'. ',TRIM(@Reason)),500));
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ChangeStop
 @StopId int,@PortId int,@Arrival datetime2,@Departure datetime2,@Reason nvarchar(500),@StaffId int AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 EXEC dbo.usp_RequireRole @StaffId,'ITINERARY';
 IF @Departure<=@Arrival THROW 51055,N'Giờ rời cảng phải sau giờ đến.',1;
 IF NULLIF(TRIM(@Reason),N'') IS NULL THROW 51056,N'Cần ghi lý do thay đổi lịch.',1;
 BEGIN TRY
  BEGIN TRAN;
  DECLARE @CruiseId int,@OldPortId int,@OldArrival datetime2,@OldDeparture datetime2,@StartDate date,@EndDate date,@PortName nvarchar(100);
  SELECT @CruiseId=s.CruiseId,@OldPortId=s.PortId,@OldArrival=s.Arrival,@OldDeparture=s.Departure,@StartDate=c.StartDate,@EndDate=c.EndDate
   FROM dbo.Stops s WITH(UPDLOCK,HOLDLOCK) JOIN dbo.Cruises c ON c.CruiseId=s.CruiseId WHERE s.StopId=@StopId;
  SELECT @PortName=Name FROM dbo.Ports WHERE PortId=@PortId;
  IF @CruiseId IS NULL OR @PortName IS NULL THROW 51057,N'Điểm dừng hoặc cảng không tồn tại.',1;
  IF CAST(@Arrival AS date)<@StartDate OR CAST(@Departure AS date)>@EndDate THROW 51058,N'Thời gian cảng phải nằm trong ngày của chuyến.',1;
  IF EXISTS(SELECT 1 FROM dbo.Stops WITH(UPDLOCK,HOLDLOCK) WHERE CruiseId=@CruiseId AND StopId<>@StopId AND Arrival<@Departure AND Departure>@Arrival)
   THROW 51059,N'Lịch mới bị chồng với một điểm dừng khác.',1;
  IF EXISTS(SELECT 1 FROM dbo.Activities WHERE StopId=@StopId AND Status<>'CANCELLED' AND (StartsAt<@Arrival OR ReturnAt>@Departure))
   THROW 51060,N'Lịch mới xung đột với tour bờ. Điều chỉnh tour trước.',1;
  IF @OldPortId<>@PortId OR @OldArrival<>@Arrival OR @OldDeparture<>@Departure
  BEGIN
   INSERT dbo.ItineraryChanges(StopId,OldArrival,OldDeparture,NewArrival,NewDeparture,Reason,StaffId,OldPortId,NewPortId,ChangeType)
    VALUES(@StopId,@OldArrival,@OldDeparture,@Arrival,@Departure,TRIM(@Reason),@StaffId,@OldPortId,@PortId,'UPDATE');
   UPDATE dbo.Stops SET PortId=@PortId,Arrival=@Arrival,Departure=@Departure WHERE StopId=@StopId;
   INSERT dbo.Notifications(CruiseId,Message) VALUES(@CruiseId,LEFT(CONCAT(N'Lịch trình cảng ',@PortName,N' đã thay đổi. ',TRIM(@Reason)),500));
  END;
  COMMIT;
 END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK; THROW; END CATCH
END;
GO
