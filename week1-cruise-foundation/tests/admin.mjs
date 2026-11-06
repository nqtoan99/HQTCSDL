import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../',import.meta.url));
const database='CruiseWeek1AdminTest';
const sqlcmd=process.env.SQLCMD_PATH||'sqlcmd';
const server=process.env.SQL_SERVER||'.';
const sql=(db,statement)=>{
 const result=spawnSync(sqlcmd,['-S',server,'-d',db,'-E','-C','-I','-b','-l','10','-Q',statement],{encoding:'utf8',windowsHide:true,env:process.env});
 if(result.error||result.status!==0)throw Error(result.error?.message||result.stderr||result.stdout);
 return result.stdout.trim();
};
const drop=()=>sql('master',`IF DB_ID(N'${database}') IS NOT NULL BEGIN ALTER DATABASE [${database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [${database}]; END;`);
const reject=async(action,message)=>{let blocked=false;try{await action();}catch{blocked=true;}assert(blocked,message);};
let checks=0;
const check=async(name,action)=>{await action();checks++;console.log('PASS '+name);};

try{
 drop();
 const setup=spawnSync(process.execPath,['scripts/setup.mjs'],{cwd:root,encoding:'utf8',windowsHide:true,env:{...process.env,SQL_DATABASE:database}});
 if(setup.error||setup.status!==0)throw Error(setup.error?.message||setup.stderr||setup.stdout);
 process.env.SQL_DATABASE=database;
 const {query,jsonQuery}=await import('../src/db.mjs?admin='+Date.now());
 const hash='a'.repeat(32)+':'+ 'b'.repeat(128);

 await check('Tạo người dùng và nhiều vai trò trong một transaction',async()=>{
  await query(`EXEC dbo.usp_AdminSaveUser @ActorId=1,@UserId=0,@Name=N'Nhân viên kiểm thử',@Email='admin-test@local.test',@Active=1,@RoleCodes='POS,FINANCE',@PasswordHash='${hash}';`);
  const users=await jsonQuery("SELECT u.UserId,u.Active,(SELECT COUNT(*) FROM UserRoles ur WHERE ur.UserId=u.UserId) RoleCount FROM Users u WHERE u.Email='admin-test@local.test' FOR JSON PATH");
  assert.equal(users[0].Active,true);assert.equal(users[0].RoleCount,2);
 });
 await check('Không cho tự khóa hoặc gỡ quản trị viên cuối cùng',()=>reject(
  ()=>query("EXEC dbo.usp_AdminSaveUser @ActorId=1,@UserId=1,@Name=N'Quản trị demo',@Email='admin@demo.local',@Active=0,@RoleCodes='ADMIN',@PasswordHash=NULL;"),
  'Quản trị viên cuối cùng vẫn tự khóa được.'
 ));

 await query("EXEC dbo.usp_AdminSaveCatalog @ActorId=1,@Entity='ship',@Id=0,@Name=N'Tàu quản trị',@Capacity=50; DECLARE @ship int=(SELECT ShipId FROM Ships WHERE Name=N'Tàu quản trị'); EXEC dbo.usp_AdminSaveCatalog @ActorId=1,@Entity='zone',@Id=0,@Name=N'Khu quản trị',@ParentId=@ship; EXEC dbo.usp_AdminSaveCatalog @ActorId=1,@Entity='cabin',@Id=0,@Name=NULL,@ParentId=@ship,@Number='QT-01';");
 await check('Danh mục khu vực và cabin lưu đúng tàu cha',async()=>{
  const rows=await jsonQuery("SELECT s.ShipId,z.ZoneId,c.CabinId FROM Ships s JOIN Zones z ON z.ShipId=s.ShipId JOIN Cabins c ON c.ShipId=s.ShipId WHERE s.Name=N'Tàu quản trị' FOR JSON PATH");
  assert(rows[0].ZoneId);assert(rows[0].CabinId);
 });
 await check('Từ chối tàu cha không tồn tại',()=>reject(
  ()=>query("EXEC dbo.usp_AdminSaveCatalog @ActorId=1,@Entity='zone',@Id=0,@Name=N'Khu sai',@ParentId=999999;"),
  'Khu vực vẫn nhận tàu không tồn tại.'
 ));

 await check('Cấu hình gói lặp lại không tạo audit giả',async()=>{
  const before=Number(await query("SELECT COUNT(*) FROM AuditLog WHERE Entity='PackageService';"));
  await query('EXEC dbo.usp_AdminPackageService @ActorId=1,@PackageId=2,@ServiceId=1,@Included=1;');
  const after=Number(await query("SELECT COUNT(*) FROM AuditLog WHERE Entity='PackageService';"));
  assert.equal(after,before);
 });
 await check('Thay đổi chính sách và mã định danh có audit',async()=>{
  await query("EXEC dbo.usp_AdminSavePolicy @ActorId=1,@CancelHours=12,@RefundPercent=80; EXEC dbo.usp_AdminSetIdentifierActive @ActorId=1,@IdentifierId=1,@Active=0;");
  const rows=await jsonQuery("SELECT (SELECT CancelHours FROM Policy WHERE PolicyId=1) CancelHours,(SELECT RefundPercent FROM Policy WHERE PolicyId=1) RefundPercent,(SELECT COUNT(*) FROM AuditLog WHERE Entity='Identifier' AND EntityId=1 AND ActorId=1) IdentifierAudits FOR JSON PATH");
  assert.equal(rows[0].CancelHours,12);assert.equal(rows[0].RefundPercent,80);assert.equal(rows[0].IdentifierAudits,1);
 });

 await query("EXEC dbo.usp_AdminSetIdentifierActive @ActorId=1,@IdentifierId=1,@Active=1; EXEC dbo.usp_PostPOS @Code='AURORA-001',@ServiceId=1,@Quantity=1,@DeviceId=1,@StaffId=2,@ClientId='11111111-1111-4111-8111-111111111111';");
 await check('Không đổi loại thiết bị đã có giao dịch',()=>reject(
  ()=>query("EXEC dbo.usp_AdminSaveCatalog @ActorId=1,@Entity='device',@Id=1,@Name=N'POS nhà hàng',@Kind='CHECKIN';"),
  'Thiết bị POS đã sử dụng vẫn đổi thành CHECKIN.'
 ));
 await query("DECLARE @transaction int=(SELECT TransactionId FROM Transactions WHERE ClientId='11111111-1111-4111-8111-111111111111'); EXEC dbo.usp_Reconcile @TransactionId=@transaction,@StaffId=4; EXEC dbo.usp_SettleAccount @AccountId=1,@ActorId=4,@Method='MOCK';");
 await check('Không sửa booking sau khi tài khoản đã chốt',()=>reject(
  ()=>query('EXEC dbo.usp_AdminSaveBooking @ActorId=1,@BookingId=1,@CruiseId=1,@UserId=6,@CabinId=1,@PackageId=1;'),
  'Booking đã chốt vẫn sửa được.'
 ));
 await query('UPDATE Users SET Active=0 WHERE UserId=1;');
 await check('Quản trị viên bị khóa không gọi được thủ tục quản trị',()=>reject(
  ()=>query('EXEC dbo.usp_AdminSavePolicy @ActorId=1,@CancelHours=2,@RefundPercent=100;'),
  'Tài khoản quản trị bị khóa vẫn thao tác được.'
 ));
 console.log(JSON.stringify({tests:checks,failures:0}));
}finally{
 try{drop();}catch(error){console.error('Không xóa được database kiểm thử:',error.message);}
}
