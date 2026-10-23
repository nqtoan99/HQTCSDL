import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../',import.meta.url));
const database='CruiseWeek1IntegrityTest';
const sqlcmd=process.env.SQLCMD_PATH||'sqlcmd';
const server=process.env.SQL_SERVER||'.';
const sql=(db,statement)=>{
 const r=spawnSync(sqlcmd,['-S',server,'-d',db,'-E','-C','-I','-b','-l','10','-Q',statement],{encoding:'utf8',windowsHide:true,env:process.env});
 if(r.error||r.status!==0)throw Error(r.error?.message||r.stderr||r.stdout);
 return r.stdout.trim();
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
 const {query,jsonQuery}=await import('../src/db.mjs?integrity='+Date.now());

 await check('Không có dữ liệu chéo bảng sai',async()=>{
  assert.equal((await query('EXEC dbo.usp_VerifyDataIntegrity;')).trim(),'0');
 });
 await check('Nhật ký có actor, chi tiết và mã liên kết',async()=>{
  await query("DECLARE @c uniqueidentifier=NEWID(); EXEC sys.sp_set_session_context @key=N'ActorId',@value=1; EXEC sys.sp_set_session_context @key=N'CorrelationId',@value=@c; UPDATE Identifiers SET Active=0 WHERE IdentifierId=1;");
  const rows=await jsonQuery("SELECT ActorId,Details,CorrelationId FROM AuditLog WHERE Entity='Identifier' AND EntityId=1 AND Action='UPDATE' FOR JSON PATH");
  assert.equal(rows.at(-1).ActorId,1);assert(rows.at(-1).Details);assert(rows.at(-1).CorrelationId);
 });

 await query("INSERT Ships(Name,Capacity) VALUES(N'Tàu kiểm thử',10); DECLARE @ship int=SCOPE_IDENTITY(); INSERT Cabins(ShipId,Number) VALUES(@ship,'TEST-01'); INSERT Zones(ShipId,Name) VALUES(@ship,N'Khu thử'); INSERT Cruises(ShipId,Name,StartDate,EndDate) VALUES(@ship,N'Chuyến thử',DATEADD(day,7,CAST(GETDATE() AS date)),DATEADD(day,11,CAST(GETDATE() AS date)));");
 await check('Chặn cabin không thuộc tàu của chuyến',()=>reject(
  ()=>query("UPDATE Bookings SET CabinId=(SELECT CabinId FROM Cabins WHERE Number='TEST-01') WHERE BookingId=1;"),
  'Booking sai tàu không bị chặn.'
 ));
 await check('Chặn khu vực hoạt động không thuộc tàu',()=>reject(
  ()=>query("UPDATE Activities SET CruiseId=(SELECT CruiseId FROM Cruises WHERE Name=N'Chuyến thử') WHERE ActivityId=1;"),
  'Hoạt động sai tàu không bị chặn.'
 ));

 await query('EXEC dbo.usp_Register @BookingId=1,@ActivityId=1,@ActorId=6;');
 await check('Chặn giao dịch gắn sai tài khoản booking',()=>reject(
  ()=>query('UPDATE Transactions SET AccountId=2 WHERE RegistrationId=(SELECT RegistrationId FROM Registrations WHERE BookingId=1 AND ActivityId=1);'),
  'Giao dịch sai tài khoản không bị chặn.'
 ));
 await check('Chặn hóa đơn có tổng sai',()=>reject(
  ()=>query('INSERT Invoices(AccountId,Total) VALUES(2,123);'),
  'Hóa đơn sai tổng không bị chặn.'
 ));

 await query("EXEC dbo.usp_SettleAccount @AccountId=1,@ActorId=1,@Method='MOCK';");
 await check('Chốt tài khoản tạo hóa đơn và thanh toán khớp',async()=>{
  const rows=await jsonQuery("SELECT ac.Status,i.Total,p.Amount,p.Method FROM Accounts ac JOIN Invoices i ON i.AccountId=ac.AccountId JOIN Payments p ON p.InvoiceId=i.InvoiceId WHERE ac.AccountId=1 FOR JSON PATH");
  assert.equal(rows[0].Status,'SETTLED');assert.equal(rows[0].Amount,rows[0].Total);assert.equal(rows[0].Method,'MOCK');
 });
 await check('Một lần chốt dùng cùng mã nhật ký',async()=>{
  const rows=await jsonQuery("SELECT COUNT(DISTINCT CorrelationId) Correlations FROM AuditLog WHERE Entity IN('Account','Invoice','Payment') AND EntityId=1 AND CorrelationId IS NOT NULL FOR JSON PATH");
  assert.equal(rows[0].Correlations,1);
 });
 await check('Chặn sửa giao dịch sau khi chốt',()=>reject(
  ()=>query('UPDATE Transactions SET Amount=Amount+1 WHERE AccountId=1;'),
  'Giao dịch tài khoản đã chốt vẫn sửa được.'
 ));
 await check('Chặn mở lại tài khoản đã chốt',()=>reject(
  ()=>query("UPDATE Accounts SET Status='OPEN' WHERE AccountId=1;"),
  'Tài khoản đã chốt vẫn mở lại được.'
 ));
 await check('Chặn sửa thanh toán sau khi chốt',()=>reject(
  ()=>query('UPDATE Payments SET Amount=Amount+1 WHERE PaymentId=1;'),
  'Thanh toán đã chốt vẫn sửa được.'
 ));
 await check('Có đủ index cho truy vấn nghiệp vụ',async()=>{
  const rows=await jsonQuery("SELECT name FROM sys.indexes WHERE name IN('IX_AuditLog_EntityCreated','IX_AuditLog_Correlation','IX_Bookings_CruiseCabin','IX_Transactions_RegistrationAccount') FOR JSON PATH");
  assert.equal(rows.length,4);
 });
 console.log(JSON.stringify({tests:checks,failures:0}));
}finally{
 try{drop();}catch(error){console.error('Không xóa được database kiểm thử:',error.message);}
}
