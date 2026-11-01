:ON ERROR EXIT
USE CruiseWeek1;
GO
SET XACT_ABORT ON;
IF COL_LENGTH('dbo.Users','PasswordHash') IS NULL ALTER TABLE dbo.Users ADD PasswordHash varchar(200) NULL;
IF COL_LENGTH('dbo.Users','Active') IS NULL ALTER TABLE dbo.Users ADD Active bit NOT NULL CONSTRAINT DF_Users_Active DEFAULT 1;
GO
BEGIN TRAN;
IF NOT EXISTS(SELECT 1 FROM Users WHERE Email='shore@demo.local') INSERT Users(Name,Email) VALUES(N'Quản lý tour bờ','shore@demo.local');
IF NOT EXISTS(SELECT 1 FROM Users WHERE Email='operations@demo.local') INSERT Users(Name,Email) VALUES(N'Quản lý vận hành','operations@demo.local');
IF NOT EXISTS(SELECT 1 FROM Users WHERE Email='posfinance@demo.local') INSERT Users(Name,Email) VALUES(N'Nhân viên POS và tài chính','posfinance@demo.local');
INSERT UserRoles(UserId,RoleId)
SELECT u.UserId,r.RoleId FROM Users u JOIN Roles r ON r.Code=CASE u.Email WHEN 'shore@demo.local' THEN 'SHORE' WHEN 'operations@demo.local' THEN 'OPERATIONS' END
WHERE u.Email IN('shore@demo.local','operations@demo.local') AND NOT EXISTS(SELECT 1 FROM UserRoles ur WHERE ur.UserId=u.UserId AND ur.RoleId=r.RoleId);
INSERT UserRoles(UserId,RoleId)
SELECT u.UserId,r.RoleId FROM Users u JOIN Roles r ON r.Code IN('POS','FINANCE')
WHERE u.Email='posfinance@demo.local' AND NOT EXISTS(SELECT 1 FROM UserRoles ur WHERE ur.UserId=u.UserId AND ur.RoleId=r.RoleId);
COMMIT;
GO
