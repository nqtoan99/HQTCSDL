:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
GO

-- BLE mô phỏng cho demo; không kết nối đầu thu/phần cứng thật.
IF OBJECT_ID(N'dbo.Wearables',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.Wearables(
  WearableId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Wearables PRIMARY KEY,
  BookingId int NOT NULL CONSTRAINT FK_Wearables_Bookings REFERENCES dbo.Bookings(BookingId),
  Code varchar(100) NOT NULL CONSTRAINT UQ_Wearables_Code UNIQUE
 );
END;
IF OBJECT_ID(N'dbo.BLEReceivers',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.BLEReceivers(
  ReceiverId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_BLEReceivers PRIMARY KEY,
  ZoneId int NOT NULL CONSTRAINT FK_BLEReceivers_Zones REFERENCES dbo.Zones(ZoneId),
  Code varchar(100) NOT NULL CONSTRAINT UQ_BLEReceivers_Code UNIQUE
 );
END;
IF OBJECT_ID(N'dbo.BLELocations',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.BLELocations(
  LocationId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_BLELocations PRIMARY KEY,
  WearableId int NOT NULL CONSTRAINT FK_BLELocations_Wearables REFERENCES dbo.Wearables(WearableId),
  ReceiverId int NOT NULL CONSTRAINT FK_BLELocations_Receivers REFERENCES dbo.BLEReceivers(ReceiverId),
  ObservedAt datetime2(3) NOT NULL CONSTRAINT DF_BLELocations_ObservedAt DEFAULT SYSUTCDATETIME()
 );
END;
GO

IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.BLELocations') AND name=N'IX_BLELocations_Wearable_ObservedAt')
 CREATE INDEX IX_BLELocations_Wearable_ObservedAt ON dbo.BLELocations(WearableId,ObservedAt DESC,LocationId DESC) INCLUDE(ReceiverId);
GO

CREATE OR ALTER VIEW dbo.vw_BLELatest AS
WITH Ranked AS(
 SELECT l.LocationId,l.WearableId,l.ReceiverId,l.ObservedAt,
  ROW_NUMBER() OVER(PARTITION BY l.WearableId ORDER BY l.ObservedAt DESC,l.LocationId DESC) AS RowNumber
 FROM dbo.BLELocations l
)
SELECT w.WearableId,w.BookingId,w.Code,rx.ReceiverId,rx.Code AS ReceiverCode,
 z.ZoneId,z.Name AS Zone,r.ObservedAt
FROM Ranked r
JOIN dbo.Wearables w ON w.WearableId=r.WearableId
JOIN dbo.BLEReceivers rx ON rx.ReceiverId=r.ReceiverId
JOIN dbo.Zones z ON z.ZoneId=rx.ZoneId
WHERE r.RowNumber=1;
GO

-- Seed vị trí giả lập cho ba booking demo; mọi INSERT đều idempotent.
DECLARE @ShipId int=(
 SELECT TOP(1) c.ShipId FROM dbo.Cruises c ORDER BY c.CruiseId
);
IF @ShipId IS NOT NULL
BEGIN
 ;WITH DemoZones AS(
  SELECT TOP(3) z.ZoneId,ROW_NUMBER() OVER(ORDER BY z.ZoneId) AS ZoneNumber
  FROM dbo.Zones z WHERE z.ShipId=@ShipId ORDER BY z.ZoneId
 )
 INSERT dbo.BLEReceivers(ZoneId,Code)
 SELECT dz.ZoneId,'RX-DEMO-'+RIGHT('00'+CONVERT(varchar(2),dz.ZoneNumber),2)
 FROM DemoZones dz
 WHERE NOT EXISTS(SELECT 1 FROM dbo.BLEReceivers rx WHERE rx.ZoneId=dz.ZoneId);

 ;WITH DemoBookings AS(
  SELECT TOP(3) b.BookingId,ROW_NUMBER() OVER(ORDER BY b.BookingId) AS WearableNumber
  FROM dbo.Bookings b JOIN dbo.Cruises c ON c.CruiseId=b.CruiseId
  WHERE c.ShipId=@ShipId ORDER BY b.BookingId
 )
 INSERT dbo.Wearables(BookingId,Code)
 SELECT db.BookingId,'BLE-DEMO-'+RIGHT('000'+CONVERT(varchar(3),db.WearableNumber),3)
 FROM DemoBookings db
 WHERE NOT EXISTS(SELECT 1 FROM dbo.Wearables w WHERE w.BookingId=db.BookingId OR w.Code='BLE-DEMO-'+RIGHT('000'+CONVERT(varchar(3),db.WearableNumber),3));

 DECLARE @Wearable1 int=(SELECT WearableId FROM dbo.Wearables WHERE Code='BLE-DEMO-001');
 DECLARE @Wearable2 int=(SELECT WearableId FROM dbo.Wearables WHERE Code='BLE-DEMO-002');
 DECLARE @Wearable3 int=(SELECT WearableId FROM dbo.Wearables WHERE Code='BLE-DEMO-003');
 DECLARE @Receiver1 int=(SELECT ReceiverId FROM dbo.BLEReceivers WHERE Code='RX-DEMO-01');
 DECLARE @Receiver2 int=(SELECT ReceiverId FROM dbo.BLEReceivers WHERE Code='RX-DEMO-02');
 DECLARE @Receiver3 int=(SELECT ReceiverId FROM dbo.BLEReceivers WHERE Code='RX-DEMO-03');
 DECLARE @Now datetime2(3)=SYSUTCDATETIME();
 DECLARE @Samples TABLE(WearableId int NULL,ReceiverId int NULL,ObservedAt datetime2(3));
 INSERT @Samples VALUES
  (@Wearable1,@Receiver1,DATEADD(minute,-20,@Now)),
  (@Wearable1,@Receiver2,DATEADD(minute,-2,@Now)),
  (@Wearable2,@Receiver1,DATEADD(minute,-4,@Now)),
  (@Wearable3,@Receiver3,DATEADD(minute,-1,@Now));
 INSERT dbo.BLELocations(WearableId,ReceiverId,ObservedAt)
 SELECT s.WearableId,s.ReceiverId,s.ObservedAt FROM @Samples s
 WHERE s.WearableId IS NOT NULL AND s.ReceiverId IS NOT NULL
  AND NOT EXISTS(SELECT 1 FROM dbo.BLELocations l WHERE l.WearableId=s.WearableId AND l.ReceiverId=s.ReceiverId);
END;
GO
