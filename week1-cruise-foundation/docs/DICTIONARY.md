# Từ điển dữ liệu

Được sinh từ metadata SQL Server đang chạy, không suy đoán cấu trúc.

## Accounts

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| AccountId | int IDENTITY | PK  | Không |  |
| BookingId | int | FK → Bookings.BookingId | Không |  |
| Status | varchar(10) |  | Không | ('OPEN') |

## Activities

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| ActivityId | int IDENTITY | PK  | Không |  |
| CruiseId | int | FK → Cruises.CruiseId | Không |  |
| ZoneId | int | FK → Zones.ZoneId | Có |  |
| StopId | int | FK → Stops.StopId | Có |  |
| ProviderId | int | FK → Providers.ProviderId | Có |  |
| Name | nvarchar(150) |  | Không |  |
| Kind | varchar(20) |  | Không |  |
| StartsAt | datetime2 |  | Không |  |
| EndsAt | datetime2 |  | Không |  |
| ReturnAt | datetime2 |  | Có |  |
| Capacity | int |  | Không |  |
| Fee | decimal(18,2) |  | Không |  |
| Status | varchar(20) |  | Không | ('OPEN') |
| IncludedServiceId | int | FK → Services.ServiceId | Có |  |

## AuditLog

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| LogId | bigint IDENTITY | PK  | Không |  |
| Entity | varchar(30) |  | Không |  |
| EntityId | int |  | Không |  |
| Action | varchar(10) |  | Không |  |
| ActorId | int |  | Có |  |
| CreatedAt | datetime2 |  | Không | (sysutcdatetime()) |
| Details | nvarchar(1000) |  | Có |  |
| CorrelationId | uniqueidentifier |  | Có |  |

## BLELocations

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| LocationId | bigint IDENTITY | PK  | Không |  |
| WearableId | int | FK → Wearables.WearableId | Không |  |
| ReceiverId | int | FK → BLEReceivers.ReceiverId | Không |  |
| ObservedAt | datetime2 |  | Không | (sysutcdatetime()) |

## BLEReceivers

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| ReceiverId | int IDENTITY | PK  | Không |  |
| ZoneId | int | FK → Zones.ZoneId | Không |  |
| Code | varchar(100) |  | Không |  |

## Bookings

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| BookingId | int IDENTITY | PK  | Không |  |
| CruiseId | int | FK → Cruises.CruiseId | Không |  |
| PassengerId | int | FK → Passengers.PassengerId | Không |  |
| CabinId | int | FK → Cabins.CabinId | Không |  |
| PackageId | int | FK → Packages.PackageId | Không |  |

## Cabins

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| CabinId | int IDENTITY | PK  | Không |  |
| ShipId | int | FK → Ships.ShipId | Không |  |
| Number | varchar(20) |  | Không |  |

## CruiseFeedback

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| BookingId | int | PK FK → Bookings.BookingId | Không |  |
| Rating | int |  | Không |  |
| Comment | nvarchar(500) |  | Không |  |
| CreatedAt | datetime2 |  | Không | (sysutcdatetime()) |

## Cruises

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| CruiseId | int IDENTITY | PK  | Không |  |
| ShipId | int | FK → Ships.ShipId | Không |  |
| Name | nvarchar(150) |  | Không |  |
| StartDate | date |  | Không |  |
| EndDate | date |  | Không |  |
| Status | varchar(20) |  | Không | ('OPEN') |

## CheckIns

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| CheckInId | int IDENTITY | PK  | Không |  |
| RegistrationId | int | FK → Registrations.RegistrationId | Không |  |
| DeviceId | int | FK → Devices.DeviceId | Không |  |
| StaffId | int | FK → Users.UserId | Không |  |
| CreatedAt | datetime2 |  | Không | (sysutcdatetime()) |
| ReturnedAt | datetime2 |  | Có |  |

## Devices

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| DeviceId | int IDENTITY | PK  | Không |  |
| Name | nvarchar(100) |  | Không |  |
| Kind | varchar(20) |  | Không |  |

## Disputes

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| DisputeId | int IDENTITY | PK  | Không |  |
| TransactionId | int | FK → Transactions.TransactionId | Không |  |
| Reason | nvarchar(500) |  | Không |  |
| Status | varchar(10) |  | Không | ('OPEN') |

## Feedback

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| FeedbackId | int IDENTITY | PK  | Không |  |
| RegistrationId | int | FK → Registrations.RegistrationId | Không |  |
| Rating | int |  | Không |  |
| Comment | nvarchar(500) |  | Không |  |

## GroupMembers

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| RegistrationId | int | PK FK → Registrations.RegistrationId | Không |  |
| GroupId | int | FK → TourGroups.GroupId | Không |  |

## Identifiers

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| IdentifierId | int IDENTITY | PK  | Không |  |
| BookingId | int | FK → Bookings.BookingId | Không |  |
| Code | varchar(100) |  | Không |  |
| Kind | varchar(10) |  | Không |  |
| Active | bit |  | Không | ((1)) |

## Invoices

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| InvoiceId | int IDENTITY | PK  | Không |  |
| AccountId | int | FK → Accounts.AccountId | Không |  |
| Total | decimal(18,2) |  | Không |  |
| CreatedAt | datetime2 |  | Không | (sysutcdatetime()) |

## ItineraryChanges

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| ChangeId | int IDENTITY | PK  | Không |  |
| StopId | int | FK → Stops.StopId | Không |  |
| OldArrival | datetime2 |  | Không |  |
| OldDeparture | datetime2 |  | Không |  |
| NewArrival | datetime2 |  | Không |  |
| NewDeparture | datetime2 |  | Không |  |
| Reason | nvarchar(500) |  | Không |  |
| StaffId | int | FK → Users.UserId | Không |  |
| CreatedAt | datetime2 |  | Không | (sysutcdatetime()) |

## NotificationReads

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| NotificationId | int | PK FK → Notifications.NotificationId | Không |  |
| UserId | int | PK FK → Users.UserId | Không |  |
| ReadAt | datetime2 |  | Không | (sysutcdatetime()) |

## Notifications

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| NotificationId | int IDENTITY | PK  | Không |  |
| CruiseId | int | FK → Cruises.CruiseId | Không |  |
| Message | nvarchar(500) |  | Không |  |
| CreatedAt | datetime2 |  | Không | (sysutcdatetime()) |

## Packages

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| PackageId | int IDENTITY | PK  | Không |  |
| Name | nvarchar(100) |  | Không |  |

## PackageServices

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| PackageId | int | PK FK → Packages.PackageId | Không |  |
| ServiceId | int | PK FK → Services.ServiceId | Không |  |

## Passengers

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| PassengerId | int IDENTITY | PK  | Không |  |
| UserId | int | FK → Users.UserId | Không |  |

## Payments

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| PaymentId | int IDENTITY | PK  | Không |  |
| InvoiceId | int | FK → Invoices.InvoiceId | Không |  |
| Amount | decimal(18,2) |  | Không |  |
| Method | varchar(20) |  | Không |  |
| CreatedAt | datetime2 |  | Không | (sysutcdatetime()) |

## Policy

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| PolicyId | int | PK  | Không |  |
| CancelHours | int |  | Không |  |
| RefundPercent | int |  | Không | ((100)) |

## Ports

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| PortId | int IDENTITY | PK  | Không |  |
| Name | nvarchar(100) |  | Không |  |

## Providers

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| ProviderId | int IDENTITY | PK  | Không |  |
| Name | nvarchar(100) |  | Không |  |

## Registrations

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| RegistrationId | int IDENTITY | PK  | Không |  |
| ActivityId | int | FK → Activities.ActivityId | Không |  |
| BookingId | int | FK → Bookings.BookingId | Không |  |
| Status | varchar(20) |  | Không |  |
| CreatedAt | datetime2 |  | Không | (sysutcdatetime()) |

## Roles

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| RoleId | int IDENTITY | PK  | Không |  |
| Code | varchar(30) |  | Không |  |
| Name | nvarchar(100) |  | Không |  |

## Services

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| ServiceId | int IDENTITY | PK  | Không |  |
| Name | nvarchar(100) |  | Không |  |
| Price | decimal(18,2) |  | Không |  |

## Ships

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| ShipId | int IDENTITY | PK  | Không |  |
| Name | nvarchar(100) |  | Không |  |
| Capacity | int |  | Không |  |

## Stops

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| StopId | int IDENTITY | PK  | Không |  |
| CruiseId | int | FK → Cruises.CruiseId | Không |  |
| PortId | int | FK → Ports.PortId | Không |  |
| Arrival | datetime2 |  | Không |  |
| Departure | datetime2 |  | Không |  |

## SyncReceipts

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| ClientId | uniqueidentifier | PK FK → Transactions.ClientId | Không |  |
| DeviceId | int | FK → Devices.DeviceId | Không |  |
| SyncedAt | datetime2 |  | Không | (sysutcdatetime()) |

## TourGroups

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| GroupId | int IDENTITY | PK  | Không |  |
| ActivityId | int | FK → Activities.ActivityId | Không |  |
| Name | nvarchar(100) |  | Không |  |
| Vehicle | nvarchar(100) |  | Không |  |
| Guide | nvarchar(100) |  | Không |  |

## Transactions

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| TransactionId | int IDENTITY | PK  | Không |  |
| AccountId | int | FK → Accounts.AccountId | Không |  |
| RegistrationId | int | FK → Registrations.RegistrationId | Có |  |
| ServiceId | int | FK → Services.ServiceId | Có |  |
| DeviceId | int | FK → Devices.DeviceId | Có |  |
| StaffId | int | FK → Users.UserId | Có |  |
| ClientId | uniqueidentifier |  | Không | (newid()) |
| Quantity | int |  | Không | ((1)) |
| Amount | decimal(18,2) |  | Không |  |
| Status | varchar(20) |  | Không | ('POSTED') |
| CreatedAt | datetime2 |  | Không | (sysutcdatetime()) |
| RefundAmount | decimal(18,2) |  | Không | ((0)) |
| SyncStatus | varchar(10) |  | Không | ('SYNCED') |
| ReconciledAt | datetime2 |  | Có |  |
| ReconciledBy | int | FK → Users.UserId | Có |  |

## UserRoles

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| UserId | int | PK FK → Users.UserId | Không |  |
| RoleId | int | PK FK → Roles.RoleId | Không |  |

## Users

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| UserId | int IDENTITY | PK  | Không |  |
| Name | nvarchar(100) |  | Không |  |
| Email | varchar(150) |  | Không |  |
| PasswordHash | varchar(200) |  | Có |  |
| Active | bit |  | Không | ((1)) |

## Wearables

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| WearableId | int IDENTITY | PK  | Không |  |
| BookingId | int | FK → Bookings.BookingId | Không |  |
| Code | varchar(100) |  | Không |  |

## Zones

| Trường | Kiểu | Khóa | Nullable | Mặc định |
|---|---|---|---|---|
| ZoneId | int IDENTITY | PK  | Không |  |
| ShipId | int | FK → Ships.ShipId | Không |  |
| Name | nvarchar(100) |  | Không |  |

