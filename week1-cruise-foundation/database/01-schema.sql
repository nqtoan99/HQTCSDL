:ON ERROR EXIT
IF DB_ID(N'CruiseWeek1') IS NULL CREATE DATABASE CruiseWeek1;
GO
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
IF OBJECT_ID('dbo.Ships') IS NOT NULL THROW 51000, N'Database đã có bảng. Không chạy lại schema trên database đang dùng.', 1;
GO
CREATE TABLE Ships(ShipId int IDENTITY PRIMARY KEY, Name nvarchar(100) NOT NULL, Capacity int NOT NULL CHECK(Capacity>0));
CREATE TABLE Zones(ZoneId int IDENTITY PRIMARY KEY, ShipId int NOT NULL REFERENCES Ships, Name nvarchar(100) NOT NULL, UNIQUE(ShipId,Name));
CREATE TABLE Cabins(CabinId int IDENTITY PRIMARY KEY, ShipId int NOT NULL REFERENCES Ships, Number varchar(20) NOT NULL, UNIQUE(ShipId,Number));
CREATE TABLE Cruises(CruiseId int IDENTITY PRIMARY KEY, ShipId int NOT NULL REFERENCES Ships, Name nvarchar(150) NOT NULL, StartDate date NOT NULL, EndDate date NOT NULL, Status varchar(20) NOT NULL DEFAULT 'OPEN' CHECK(Status IN('OPEN','SAILING','CLOSED')), CHECK(EndDate>=StartDate));
CREATE TABLE Ports(PortId int IDENTITY PRIMARY KEY, Name nvarchar(100) NOT NULL UNIQUE);
CREATE TABLE Stops(StopId int IDENTITY PRIMARY KEY, CruiseId int NOT NULL REFERENCES Cruises, PortId int NOT NULL REFERENCES Ports, Arrival datetime2 NOT NULL, Departure datetime2 NOT NULL, CHECK(Departure>Arrival), UNIQUE(CruiseId,PortId,Arrival));
CREATE TABLE Roles(RoleId int IDENTITY PRIMARY KEY, Code varchar(30) NOT NULL UNIQUE, Name nvarchar(100) NOT NULL);
CREATE TABLE Users(UserId int IDENTITY PRIMARY KEY, Name nvarchar(100) NOT NULL, Email varchar(150) NOT NULL UNIQUE);
CREATE TABLE UserRoles(UserId int NOT NULL REFERENCES Users, RoleId int NOT NULL REFERENCES Roles, PRIMARY KEY(UserId,RoleId));
CREATE TABLE Passengers(PassengerId int IDENTITY PRIMARY KEY, UserId int NOT NULL UNIQUE REFERENCES Users);
CREATE TABLE Packages(PackageId int IDENTITY PRIMARY KEY, Name nvarchar(100) NOT NULL UNIQUE);
CREATE TABLE Bookings(BookingId int IDENTITY PRIMARY KEY, CruiseId int NOT NULL REFERENCES Cruises, PassengerId int NOT NULL REFERENCES Passengers, CabinId int NOT NULL REFERENCES Cabins, PackageId int NOT NULL REFERENCES Packages, UNIQUE(CruiseId,PassengerId));
CREATE TABLE Providers(ProviderId int IDENTITY PRIMARY KEY, Name nvarchar(100) NOT NULL);
CREATE TABLE Activities(ActivityId int IDENTITY PRIMARY KEY, CruiseId int NOT NULL REFERENCES Cruises, ZoneId int NULL REFERENCES Zones, StopId int NULL REFERENCES Stops, ProviderId int NULL REFERENCES Providers, Name nvarchar(150) NOT NULL, Kind varchar(20) NOT NULL CHECK(Kind IN('ONBOARD','SHORE')), StartsAt datetime2 NOT NULL, EndsAt datetime2 NOT NULL, ReturnAt datetime2 NULL, Capacity int NOT NULL CHECK(Capacity>0), Fee decimal(18,2) NOT NULL CHECK(Fee>=0), Status varchar(20) NOT NULL DEFAULT 'OPEN' CHECK(Status IN('OPEN','CANCELLED','COMPLETED','DELAYED')), CHECK(EndsAt>StartsAt), CHECK((Kind='ONBOARD' AND ZoneId IS NOT NULL AND StopId IS NULL AND ProviderId IS NULL) OR (Kind='SHORE' AND StopId IS NOT NULL AND ProviderId IS NOT NULL AND ReturnAt IS NOT NULL AND ReturnAt>=EndsAt)));
CREATE TABLE Services(ServiceId int IDENTITY PRIMARY KEY, Name nvarchar(100) NOT NULL, Price decimal(18,2) NOT NULL CHECK(Price>=0));
CREATE TABLE PackageServices(PackageId int NOT NULL REFERENCES Packages, ServiceId int NOT NULL REFERENCES Services, PRIMARY KEY(PackageId,ServiceId));
CREATE TABLE Policy(PolicyId int PRIMARY KEY CHECK(PolicyId=1), CancelHours int NOT NULL CHECK(CancelHours>=0));
CREATE TABLE Registrations(RegistrationId int IDENTITY PRIMARY KEY, ActivityId int NOT NULL REFERENCES Activities, BookingId int NOT NULL REFERENCES Bookings, Status varchar(20) NOT NULL CHECK(Status IN('CONFIRMED','WAITLIST','CANCELLED')), CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME(), UNIQUE(ActivityId,BookingId));
CREATE TABLE Devices(DeviceId int IDENTITY PRIMARY KEY, Name nvarchar(100) NOT NULL, Kind varchar(20) NOT NULL CHECK(Kind IN('POS','CHECKIN')));
CREATE TABLE Identifiers(IdentifierId int IDENTITY PRIMARY KEY, BookingId int NOT NULL REFERENCES Bookings, Code varchar(100) NOT NULL UNIQUE, Kind varchar(10) NOT NULL CHECK(Kind IN('QR','CARD','NFC')), Active bit NOT NULL DEFAULT 1);
CREATE TABLE CheckIns(CheckInId int IDENTITY PRIMARY KEY, RegistrationId int NOT NULL UNIQUE REFERENCES Registrations, DeviceId int NOT NULL REFERENCES Devices, StaffId int NOT NULL REFERENCES Users, CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME(), ReturnedAt datetime2 NULL);
CREATE TABLE Accounts(AccountId int IDENTITY PRIMARY KEY, BookingId int NOT NULL UNIQUE REFERENCES Bookings, Status varchar(10) NOT NULL DEFAULT 'OPEN' CHECK(Status IN('OPEN','SETTLED')));
CREATE TABLE Transactions(TransactionId int IDENTITY PRIMARY KEY, AccountId int NOT NULL REFERENCES Accounts, RegistrationId int NULL REFERENCES Registrations, ServiceId int NULL REFERENCES Services, DeviceId int NULL REFERENCES Devices, StaffId int NULL REFERENCES Users, ClientId uniqueidentifier NOT NULL UNIQUE DEFAULT NEWID(), Quantity int NOT NULL DEFAULT 1 CHECK(Quantity>0), Amount decimal(18,2) NOT NULL CHECK(Amount>=0), Status varchar(20) NOT NULL DEFAULT 'POSTED' CHECK(Status IN('POSTED','VOID','REFUNDED')), CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME(), CHECK((RegistrationId IS NOT NULL AND ServiceId IS NULL) OR (RegistrationId IS NULL AND ServiceId IS NOT NULL AND DeviceId IS NOT NULL AND StaffId IS NOT NULL)));
CREATE UNIQUE INDEX UX_Transactions_RegistrationId ON Transactions(RegistrationId) WHERE RegistrationId IS NOT NULL;
CREATE TABLE Disputes(DisputeId int IDENTITY PRIMARY KEY, TransactionId int NOT NULL REFERENCES Transactions, Reason nvarchar(500) NOT NULL, Status varchar(10) NOT NULL DEFAULT 'OPEN' CHECK(Status IN('OPEN','RESOLVED')));
CREATE TABLE Invoices(InvoiceId int IDENTITY PRIMARY KEY, AccountId int NOT NULL UNIQUE REFERENCES Accounts, Total decimal(18,2) NOT NULL CHECK(Total>=0), CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
CREATE TABLE Payments(PaymentId int IDENTITY PRIMARY KEY, InvoiceId int NOT NULL UNIQUE REFERENCES Invoices, Amount decimal(18,2) NOT NULL CHECK(Amount>=0), Method varchar(20) NOT NULL, CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
CREATE TABLE Notifications(NotificationId int IDENTITY PRIMARY KEY, CruiseId int NOT NULL REFERENCES Cruises, Message nvarchar(500) NOT NULL, CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
CREATE TABLE ItineraryChanges(ChangeId int IDENTITY PRIMARY KEY, StopId int NOT NULL REFERENCES Stops, OldArrival datetime2 NOT NULL, OldDeparture datetime2 NOT NULL, NewArrival datetime2 NOT NULL, NewDeparture datetime2 NOT NULL, Reason nvarchar(500) NOT NULL, StaffId int NOT NULL REFERENCES Users, CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
CREATE TABLE Feedback(FeedbackId int IDENTITY PRIMARY KEY, RegistrationId int NOT NULL UNIQUE REFERENCES Registrations, Rating int NOT NULL CHECK(Rating BETWEEN 1 AND 5), Comment nvarchar(500) NOT NULL);
CREATE TABLE AuditLog(LogId bigint IDENTITY PRIMARY KEY, Entity varchar(30) NOT NULL, EntityId int NOT NULL, Action varchar(10) NOT NULL, ActorId int NULL, CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
CREATE INDEX IX_Registrations_ActivityStatus ON Registrations(ActivityId,Status);
CREATE INDEX IX_Transactions_AccountStatus ON Transactions(AccountId,Status) INCLUDE(Amount);
CREATE INDEX IX_Activities_CruiseStart ON Activities(CruiseId,StartsAt);
GO
CREATE TRIGGER tr_RegistrationAudit ON Registrations AFTER INSERT,UPDATE,DELETE AS
INSERT AuditLog(Entity,EntityId,Action,ActorId) SELECT 'Registration',COALESCE(i.RegistrationId,d.RegistrationId),CASE WHEN d.RegistrationId IS NULL THEN 'INSERT' WHEN i.RegistrationId IS NULL THEN 'DELETE' ELSE 'UPDATE' END,TRY_CONVERT(int,SESSION_CONTEXT(N'ActorId')) FROM inserted i FULL JOIN deleted d ON i.RegistrationId=d.RegistrationId;
GO
CREATE TRIGGER tr_TransactionAudit ON Transactions AFTER INSERT,UPDATE,DELETE AS
INSERT AuditLog(Entity,EntityId,Action,ActorId) SELECT 'Transaction',COALESCE(i.TransactionId,d.TransactionId),CASE WHEN d.TransactionId IS NULL THEN 'INSERT' WHEN i.TransactionId IS NULL THEN 'DELETE' ELSE 'UPDATE' END,TRY_CONVERT(int,SESSION_CONTEXT(N'ActorId')) FROM inserted i FULL JOIN deleted d ON i.TransactionId=d.TransactionId;
GO
CREATE TRIGGER tr_UserRoleAudit ON UserRoles AFTER INSERT,DELETE AS
INSERT AuditLog(Entity,EntityId,Action,ActorId) SELECT 'UserRole',UserId,'INSERT',TRY_CONVERT(int,SESSION_CONTEXT(N'ActorId')) FROM inserted UNION ALL SELECT 'UserRole',UserId,'DELETE',TRY_CONVERT(int,SESSION_CONTEXT(N'ActorId')) FROM deleted;
GO
