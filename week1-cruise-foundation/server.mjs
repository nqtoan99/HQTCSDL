// Nền tảng đăng nhập, Tổng quan và quản lý chuyến/lịch trình trên SQL Server.
import http from 'node:http';
import {readFile} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {query,jsonQuery,literal,verifyPassword} from './src/db.mjs';
const root=fileURLToPath(new URL('./public/',import.meta.url));
const port=Number(process.env.PORT||3001),cookieName='aurora_week1';
const sessions=new Map(),attempts=new Map(),ttl=Number(process.env.SESSION_TTL_SECONDS||28800)*1000;
if(!Number.isInteger(port)||port<1||port>65535||!Number.isFinite(ttl)||ttl<1000)throw Error('PORT hoặc SESSION_TTL_SECONDS không hợp lệ.');
const roles={PASSENGER:'Hành khách',ITINERARY:'Điều phối hành trình',ACTIVITY:'Quản lý hoạt động',SHORE:'Quản lý tour bờ',POS:'Nhân viên POS',FINANCE:'Tài chính – Lễ tân',OPERATIONS:'Quản lý vận hành',ADMIN:'Quản trị hệ thống'};
const fail=(status,message)=>{throw Object.assign(Error(message),{status});};
const id=v=>{const n=Number(v);if(!Number.isSafeInteger(n)||n<1)fail(400,'ID không hợp lệ.');return n;};
const maybeId=v=>v===undefined||v===null||v===''?0:(Number.isSafeInteger(Number(v))&&Number(v)>=0?Number(v):fail(400,'ID không hợp lệ.'));
const text=(v,max)=>{if(typeof v!=='string'||!v.trim()||v.length>max)fail(400,'Dữ liệu không hợp lệ.');return v;};
function dateOnly(v){const s=text(v,10).trim();if(!/^\d{4}-\d{2}-\d{2}$/.test(s))fail(400,'Ngày không hợp lệ.');const d=new Date(`${s}T00:00:00Z`);if(Number.isNaN(d.getTime())||d.toISOString().slice(0,10)!==s)fail(400,'Ngày không hợp lệ.');return s;}
function dateTime(v){const s=text(v,19).trim(),m=/^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(s);if(!m)fail(400,'Giờ cảng không hợp lệ.');dateOnly(m[1]);if(Number(m[2])>23||Number(m[3])>59||Number(m[4]||0)>59)fail(400,'Giờ cảng không hợp lệ.');return `${m[1]}T${m[2]}:${m[3]}:${m[4]||'00'}`;}
async function requestJson(req){let raw='';for await(const chunk of req){raw+=chunk;if(raw.length>20000)fail(413,'Yêu cầu quá lớn.');}let body;try{body=JSON.parse(raw||'{}');}catch{fail(400,'JSON không hợp lệ.');}if(!body||typeof body!=='object'||Array.isArray(body))fail(400,'Dữ liệu gửi lên không hợp lệ.');return body;}
async function runProcedure(sql){try{await query(sql);}catch(e){const message=String(e.message||'');const match=/Msg \d+, Level 16,[\s\S]*?Line \d+\s*\r?\n([^\r\n]+)/.exec(message);if(match)fail(422,match[1].trim());throw e;}}
const sessionId=req=>new RegExp(`(?:^|;\\s*)${cookieName}=([a-f0-9]{64})(?:;|$)`).exec(req.headers.cookie||'')?.[1];
function requireRoles(u,...allowed){if(!u.roles.includes('ADMIN')&&!allowed.some(r=>u.roles.includes(r)))fail(403,'Không có quyền truy cập chức năng này.');}
async function getUser(req){
 const sid=sessionId(req),s=sessions.get(sid);if(!s||s.expires<=Date.now()){sessions.delete(sid);return null;}
 const u=(await jsonQuery(`SELECT u.UserId,u.Name,u.Email,JSON_QUERY((SELECT r.Code FROM UserRoles ur JOIN Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=u.UserId FOR JSON PATH)) AS roles FROM Users u WHERE u.UserId=${s.userId} AND u.Active=1 FOR JSON PATH`))[0];
 if(!u){sessions.delete(sid);return null;}u.roles=u.roles.map(r=>r.Code).filter(r=>Object.hasOwn(roles,r));if(!u.roles.length)fail(403,'Tài khoản chưa được cấp vai trò.');return u;
}
function bookingQuery(u,bid){
 const guest=u.roles.includes('PASSENGER')&&!u.roles.includes('ADMIN');
 return `SELECT b.BookingId,b.CruiseId,b.CabinId,b.PackageId,p.UserId,u.Name,c.Name AS Cruise,cb.Number AS Cabin,pk.Name AS Package FROM Bookings b JOIN Passengers p ON p.PassengerId=b.PassengerId JOIN Users u ON u.UserId=p.UserId JOIN Cruises c ON c.CruiseId=b.CruiseId JOIN Cabins cb ON cb.CabinId=b.CabinId JOIN Packages pk ON pk.PackageId=b.PackageId WHERE ${guest?`p.UserId=${u.UserId}`:'1=1'}${bid===undefined?'':` AND b.BookingId=${id(bid)}`}`;
}
async function state(u){
 const guest=u.roles.includes('PASSENGER')&&!u.roles.includes('ADMIN');
 const bs=guest?`SELECT b.BookingId FROM Bookings b JOIN Passengers p ON p.PassengerId=b.PassengerId WHERE p.UserId=${u.UserId}`:'SELECT BookingId FROM Bookings';
 const cs=guest?`SELECT CruiseId FROM Bookings WHERE BookingId IN(${bs})`:'SELECT CruiseId FROM Cruises';
 const guests=u.roles.some(r=>['PASSENGER','ACTIVITY','SHORE','FINANCE','OPERATIONS','ADMIN'].includes(r));
 const money=u.roles.some(r=>['PASSENGER','FINANCE','ADMIN'].includes(r));
 const itineraryAccess=u.roles.some(r=>['ITINERARY','ADMIN'].includes(r));
 const kind=u.roles.includes('ADMIN')?'':u.roles.includes('ACTIVITY')&&!u.roles.includes('SHORE')?" AND Kind='ONBOARD'":u.roles.includes('SHORE')&&!u.roles.includes('ACTIVITY')?" AND Kind='SHORE'":'';
 const registrationStats=guest
  ?`SELECT r.RegistrationId,a.ActivityId,a.CruiseId,r.BookingId,r.Status,r.PriceAtRegistration,r.CreatedAt,CASE WHEN r.Status='CONFIRMED' THEN 1 ELSE 0 END AS Confirmed,CASE WHEN r.Status='WAITLIST' THEN 1 ELSE 0 END AS Waitlist,CASE WHEN r.Status='WAITLIST' THEN (SELECT COUNT(*) FROM Registrations w WHERE w.ActivityId=r.ActivityId AND w.Status='WAITLIST' AND (w.CreatedAt<r.CreatedAt OR (w.CreatedAt=r.CreatedAt AND w.RegistrationId<=r.RegistrationId))) END AS WaitlistPosition FROM Activities a JOIN Registrations r ON r.ActivityId=a.ActivityId JOIN Bookings b ON b.BookingId=r.BookingId JOIN Passengers p ON p.PassengerId=b.PassengerId WHERE a.CruiseId IN(${cs}) AND p.UserId=${u.UserId}${kind}`
  :`SELECT a.ActivityId,a.CruiseId,SUM(CASE WHEN r.Status='CONFIRMED' THEN 1 ELSE 0 END) AS Confirmed,SUM(CASE WHEN r.Status='WAITLIST' THEN 1 ELSE 0 END) AS Waitlist FROM Activities a LEFT JOIN Registrations r ON r.ActivityId=a.ActivityId WHERE a.CruiseId IN(${cs})${kind} GROUP BY a.ActivityId,a.CruiseId`;
 const historyQuery=itineraryAccess?`SELECT h.ChangeId,h.CruiseId,h.ChangeType,h.Subject,h.OldSchedule,h.NewSchedule,h.Reason,h.Staff,h.CreatedAt FROM (
  SELECT cc.ChangeId,cc.CruiseId,cc.ChangeType,CONCAT(N'Chuyến: ',cc.NewName) AS Subject,
   CASE WHEN cc.ChangeType='CREATE' THEN N'—' ELSE CONCAT(cc.OldName,N' · ',CONVERT(nvarchar(10),cc.OldStartDate,23),N' — ',CONVERT(nvarchar(10),cc.OldEndDate,23),N' · ',cc.OldStatus) END AS OldSchedule,
   CONCAT(cc.NewName,N' · ',CONVERT(nvarchar(10),cc.NewStartDate,23),N' — ',CONVERT(nvarchar(10),cc.NewEndDate,23),N' · ',cc.NewStatus) AS NewSchedule,
   cc.Reason,u.Name AS Staff,cc.CreatedAt FROM dbo.CruiseChanges cc JOIN dbo.Users u ON u.UserId=cc.StaffId
  UNION ALL
  SELECT ic.ChangeId,s.CruiseId,ic.ChangeType,CONCAT(N'Điểm dừng: ',COALESCE(np.Name,op.Name,p.Name,N'—')),
   CASE WHEN ic.ChangeType='CREATE' THEN N'—' ELSE CONCAT(COALESCE(op.Name,p.Name,N'—'),N' · ',CONVERT(nvarchar(16),ic.OldArrival,120),N' → ',CONVERT(nvarchar(16),ic.OldDeparture,120)) END,
   CONCAT(COALESCE(np.Name,p.Name,N'—'),N' · ',CONVERT(nvarchar(16),ic.NewArrival,120),N' → ',CONVERT(nvarchar(16),ic.NewDeparture,120)),
   ic.Reason,u.Name,ic.CreatedAt FROM dbo.ItineraryChanges ic JOIN dbo.Stops s ON s.StopId=ic.StopId JOIN dbo.Users u ON u.UserId=ic.StaffId
   LEFT JOIN dbo.Ports op ON op.PortId=ic.OldPortId LEFT JOIN dbo.Ports np ON np.PortId=ic.NewPortId LEFT JOIN dbo.Ports p ON p.PortId=s.PortId
 ) h WHERE h.CruiseId IN(${cs}) ORDER BY h.CreatedAt DESC`:`SELECT CAST(NULL AS bigint) AS ChangeId,CAST(NULL AS int) AS CruiseId,CAST(NULL AS varchar(10)) AS ChangeType,CAST(NULL AS nvarchar(200)) AS Subject,CAST(NULL AS nvarchar(500)) AS OldSchedule,CAST(NULL AS nvarchar(500)) AS NewSchedule,CAST(NULL AS nvarchar(500)) AS Reason,CAST(NULL AS nvarchar(100)) AS Staff,CAST(NULL AS datetime2) AS CreatedAt WHERE 1=0`;
 const cols={cruises:`SELECT c.*,s.Name AS Ship FROM Cruises c JOIN Ships s ON s.ShipId=c.ShipId WHERE c.CruiseId IN(${cs})`,ships:'SELECT ShipId,Name,Capacity FROM Ships',ports:'SELECT PortId,Name FROM Ports',stops:`SELECT s.StopId,s.CruiseId,s.PortId,p.Name AS Port,s.Arrival,s.Departure FROM Stops s JOIN Ports p ON p.PortId=s.PortId WHERE s.CruiseId IN(${cs})`,activities:`SELECT a.*,COALESCE(z.Name,p.Name,N'—') AS Location FROM Activities a LEFT JOIN Zones z ON z.ZoneId=a.ZoneId LEFT JOIN Stops st ON st.StopId=a.StopId LEFT JOIN Ports p ON p.PortId=st.PortId WHERE a.CruiseId IN(${cs})${kind}`,registrations:registrationStats,notifications:`SELECT NotificationId,CruiseId,Message,CreatedAt FROM Notifications WHERE CruiseId IN(${cs})`,changes:historyQuery,services:'SELECT * FROM Services',packageServices:'SELECT PackageId,ServiceId FROM PackageServices',
  bookings:bookingQuery(u)+(guests?'':' AND 1=0'),accounts:`SELECT AccountId,BookingId,Status FROM Accounts WHERE BookingId IN(${bs})${money?'':' AND 1=0'}`,
  transactions:`SELECT t.TransactionId,t.AccountId,t.Amount,t.Status,t.CreatedAt,COALESCE(s.Name,a.Name,N'Dịch vụ') AS Description FROM Transactions t JOIN Accounts ac ON ac.AccountId=t.AccountId LEFT JOIN Services s ON s.ServiceId=t.ServiceId LEFT JOIN Registrations r ON r.RegistrationId=t.RegistrationId LEFT JOIN Activities a ON a.ActivityId=r.ActivityId WHERE ac.BookingId IN(${bs})${money?'':' AND 1=0'}`};
 const out=await jsonQuery('SELECT '+Object.entries(cols).map(([k,sql])=>`JSON_QUERY((${sql} FOR JSON PATH)) AS [${k}]`).join(',')+' FOR JSON PATH,WITHOUT_ARRAY_WRAPPER');
 for(const k of Object.keys(cols))if(!Array.isArray(out[k]))out[k]=[];return out;
}
const server=http.createServer(async(req,res)=>{
 const send=(status,data)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(data));};
 try{
  const url=new URL(req.url,`http://localhost:${port}`);
  if(req.method==='POST'&&req.headers.origin&&![`http://localhost:${port}`,`http://127.0.0.1:${port}`].includes(req.headers.origin))fail(403,'Nguồn yêu cầu không hợp lệ.');
  if(url.pathname==='/api/login'&&req.method==='POST'){
   const b=await requestJson(req);
   const email=text(b.email,150).trim(),password=text(b.password,100),key=req.socket.remoteAddress,t=attempts.get(key);
   if(t&&Date.now()-t.time<60000&&t.count>=15)fail(429,'Thử lại sau một phút.');
   const u=(await jsonQuery(`SELECT UserId,PasswordHash FROM Users WHERE Email=${literal(email)} AND Active=1 FOR JSON PATH`))[0];
   if(!u||!verifyPassword(password,u.PasswordHash)){const a=t&&Date.now()-t.time<60000?t:{count:0,time:Date.now()};a.count++;attempts.set(key,a);fail(401,'Email hoặc mật khẩu không đúng.');}
   const granted=await jsonQuery(`SELECT r.Code FROM UserRoles ur JOIN Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=${u.UserId} FOR JSON PATH`);
   if(!granted.some(r=>Object.hasOwn(roles,r.Code)))fail(403,'Tài khoản chưa được cấp vai trò.');
   attempts.delete(key);sessions.delete(sessionId(req));const sid=randomBytes(32).toString('hex');sessions.set(sid,{userId:u.UserId,expires:Date.now()+ttl});
   res.setHeader('Set-Cookie',`${cookieName}=${sid}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${Math.floor(ttl/1000)}`);return send(200,{ok:true});
  }
  if(url.pathname==='/api/logout'&&req.method==='POST'){sessions.delete(sessionId(req));res.setHeader('Set-Cookie',`${cookieName}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0`);return send(200,{ok:true});}
  if(url.pathname.startsWith('/api/')){
   const u=await getUser(req);if(!u)fail(401,'Vui lòng đăng nhập.');
   if(req.method==='POST'&&url.pathname==='/api/itinerary/cruises'){
    requireRoles(u,'ITINERARY');const b=await requestJson(req),cruiseId=maybeId(b.cruiseId),shipId=id(b.shipId),name=text(b.name,150).trim(),startDate=dateOnly(b.startDate),endDate=dateOnly(b.endDate),status=text(b.status,20).trim().toUpperCase(),reason=text(b.reason,500).trim();
    if(endDate<startDate)fail(400,'Ngày kết thúc phải bằng hoặc sau ngày bắt đầu.');
    await runProcedure(`EXEC dbo.usp_SaveCruise @CruiseId=${cruiseId},@ShipId=${shipId},@Name=${literal(name)},@StartDate=${literal(startDate)},@EndDate=${literal(endDate)},@Status=${literal(status)},@Reason=${literal(reason)},@StaffId=${u.UserId};`);
    return send(200,{ok:true});
   }
   if(req.method==='POST'&&url.pathname==='/api/itinerary/stops'){
    requireRoles(u,'ITINERARY');const b=await requestJson(req),stopId=maybeId(b.stopId),cruiseId=id(b.cruiseId),portId=id(b.portId),arrival=dateTime(b.arrival),departure=dateTime(b.departure),reason=text(b.reason,500).trim();
    if(departure<=arrival)fail(400,'Giờ rời cảng phải sau giờ đến.');
    const sql=stopId===0
     ?`EXEC dbo.usp_AddStop @CruiseId=${cruiseId},@PortId=${portId},@Arrival=${literal(arrival)},@Departure=${literal(departure)},@Reason=${literal(reason)},@StaffId=${u.UserId};`
     :`EXEC dbo.usp_ChangeStop @StopId=${stopId},@PortId=${portId},@Arrival=${literal(arrival)},@Departure=${literal(departure)},@Reason=${literal(reason)},@StaffId=${u.UserId};`;
    await runProcedure(sql);return send(200,{ok:true});
   }
   if(req.method==='POST'&&url.pathname==='/api/registrations'){
    requireRoles(u,'PASSENGER');const b=await requestJson(req),bookingId=id(b.bookingId),activityId=id(b.activityId);
    const allowed=await jsonQuery(bookingQuery(u,bookingId)+' FOR JSON PATH');
    if(!allowed.length)fail(403,'Không có quyền đăng ký cho booking này.');
    await runProcedure(`EXEC dbo.usp_Register @BookingId=${bookingId},@ActivityId=${activityId},@ActorId=${u.UserId};`);
    const rows=await jsonQuery(`SELECT r.RegistrationId,r.ActivityId,r.BookingId,r.Status,r.PriceAtRegistration,r.CreatedAt,CASE WHEN r.Status='WAITLIST' THEN (SELECT COUNT(*) FROM dbo.Registrations w WHERE w.ActivityId=r.ActivityId AND w.Status='WAITLIST' AND (w.CreatedAt<r.CreatedAt OR (w.CreatedAt=r.CreatedAt AND w.RegistrationId<=r.RegistrationId))) END AS WaitlistPosition FROM dbo.Registrations r WHERE r.BookingId=${bookingId} AND r.ActivityId=${activityId} FOR JSON PATH`);
    return send(201,rows[0]);
   }
   const cancelMatch=/^\/api\/registrations\/(\d+)\/cancel$/.exec(url.pathname);
   if(req.method==='POST'&&cancelMatch){
    const registrationId=id(cancelMatch[1]),body=await requestJson(req),reason=text(body.reason,500).trim();
    await runProcedure(`EXEC dbo.usp_CancelRegistration @RegistrationId=${registrationId},@ActorId=${u.UserId},@Reason=${literal(reason)};`);
    const rows=await jsonQuery(`SELECT RegistrationId,Status,CancelledAt,CancelledBy,CancelReason,RefundAmount FROM dbo.Registrations WHERE RegistrationId=${registrationId} FOR JSON PATH`);
    return send(200,rows[0]);
   }
   if(req.method!=='GET')fail(405,'Phương thức không được hỗ trợ cho API này.');
   if(url.pathname==='/api/me')return send(200,u);
   if(url.pathname==='/api/state')return send(200,await state(u));
   if(url.pathname==='/api/admin/users'){requireRoles(u,'ADMIN');return send(200,await jsonQuery('SELECT u.UserId,u.Name,u.Email,u.Active,JSON_QUERY((SELECT r.Code FROM UserRoles ur JOIN Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=u.UserId FOR JSON PATH)) AS roles FROM Users u FOR JSON PATH'));}
   if(url.pathname.startsWith('/api/departments/')){const role=url.pathname.slice('/api/departments/'.length);if(!Object.hasOwn(roles,role))fail(404,'Bộ phận không tồn tại.');requireRoles(u,role);return send(200,{role,name:roles[role],message:'Quyền truy cập đã được kiểm tra tại backend.'});}
   if(/^\/api\/bookings\/[^/]+$/.test(url.pathname)){requireRoles(u,'PASSENGER','FINANCE');const rows=await jsonQuery(bookingQuery(u,url.pathname.split('/').pop())+' FOR JSON PATH');if(!rows.length)fail(403,'Không có quyền xem đặt chỗ này hoặc đặt chỗ không tồn tại.');return send(200,rows[0]);}
   fail(404,'API chưa được triển khai trong mốc hiện tại.');
  }
  if(req.method!=='GET')fail(405,'Method không hỗ trợ.');
  const file=path.resolve(root,'.'+(url.pathname==='/'?'/index.html':decodeURIComponent(url.pathname)));
  if(!file.startsWith(root))fail(403,'Không được phép truy cập.');
  const data=await readFile(file);res.writeHead(200,{'Content-Type':({'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8'})[path.extname(file)]||'application/octet-stream','Cache-Control':'no-cache','X-Content-Type-Options':'nosniff'});res.end(data);
 }catch(e){const status=e.status||(e.code==='ENOENT'?404:503);send(status,{error:status===503?'Chưa kết nối được database. Kiểm tra SQL Server và chạy npm run setup.':e.message});}
});
await query('SELECT TOP(1) PasswordHash,Active FROM Users;');
server.listen(port,'127.0.0.1',()=>console.log(`Aurora Cruise: http://localhost:${port}`));
setInterval(()=>{for(const [id,s] of sessions)if(s.expires<=Date.now())sessions.delete(id);for(const [key,t] of attempts)if(Date.now()-t.time>=60000)attempts.delete(key);},60000).unref();
