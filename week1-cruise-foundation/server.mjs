// Phần đăng nhập được tách từ cruise-sql; chỉ có API đọc dữ liệu trong mốc này.
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
const text=(v,max)=>{if(typeof v!=='string'||!v.trim()||v.length>max)fail(400,'Dữ liệu đăng nhập không hợp lệ.');return v;};
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
 const kind=u.roles.includes('ADMIN')?'':u.roles.includes('ACTIVITY')&&!u.roles.includes('SHORE')?" AND Kind='ONBOARD'":u.roles.includes('SHORE')&&!u.roles.includes('ACTIVITY')?" AND Kind='SHORE'":'';
 const registrationStats=guest
  ?`SELECT a.ActivityId,a.CruiseId,r.BookingId,SUM(CASE WHEN r.Status='CONFIRMED' THEN 1 ELSE 0 END) AS Confirmed,SUM(CASE WHEN r.Status='WAITLIST' THEN 1 ELSE 0 END) AS Waitlist FROM Activities a JOIN Registrations r ON r.ActivityId=a.ActivityId JOIN Bookings b ON b.BookingId=r.BookingId JOIN Passengers p ON p.PassengerId=b.PassengerId WHERE a.CruiseId IN(${cs}) AND p.UserId=${u.UserId}${kind} GROUP BY a.ActivityId,a.CruiseId,r.BookingId`
  :`SELECT a.ActivityId,a.CruiseId,SUM(CASE WHEN r.Status='CONFIRMED' THEN 1 ELSE 0 END) AS Confirmed,SUM(CASE WHEN r.Status='WAITLIST' THEN 1 ELSE 0 END) AS Waitlist FROM Activities a LEFT JOIN Registrations r ON r.ActivityId=a.ActivityId WHERE a.CruiseId IN(${cs})${kind} GROUP BY a.ActivityId,a.CruiseId`;
 const cols={cruises:`SELECT c.*,s.Name AS Ship FROM Cruises c JOIN Ships s ON s.ShipId=c.ShipId WHERE c.CruiseId IN(${cs})`,stops:`SELECT s.StopId,s.CruiseId,p.Name AS Port,s.Arrival,s.Departure FROM Stops s JOIN Ports p ON p.PortId=s.PortId WHERE s.CruiseId IN(${cs})`,activities:`SELECT * FROM Activities WHERE CruiseId IN(${cs})${kind}`,registrations:registrationStats,notifications:`SELECT NotificationId,CruiseId,Message,CreatedAt FROM Notifications WHERE CruiseId IN(${cs})`,services:'SELECT * FROM Services',
  bookings:bookingQuery(u)+(guests?'':' AND 1=0'),accounts:`SELECT AccountId,BookingId,Status FROM Accounts WHERE BookingId IN(${bs})${money?'':' AND 1=0'}`,
  transactions:`SELECT t.TransactionId,t.AccountId,t.Amount,t.Status,t.CreatedAt FROM Transactions t JOIN Accounts ac ON ac.AccountId=t.AccountId WHERE ac.BookingId IN(${bs})${money?'':' AND 1=0'}`};
 const out=await jsonQuery('SELECT '+Object.entries(cols).map(([k,sql])=>`JSON_QUERY((${sql} FOR JSON PATH)) AS [${k}]`).join(',')+' FOR JSON PATH,WITHOUT_ARRAY_WRAPPER');
 for(const k of Object.keys(cols))if(!Array.isArray(out[k]))out[k]=[];return out;
}
const server=http.createServer(async(req,res)=>{
 const send=(status,data)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(data));};
 try{
  const url=new URL(req.url,`http://localhost:${port}`);
  if(req.method==='POST'&&req.headers.origin&&![`http://localhost:${port}`,`http://127.0.0.1:${port}`].includes(req.headers.origin))fail(403,'Nguồn yêu cầu không hợp lệ.');
  if(url.pathname==='/api/login'&&req.method==='POST'){
   let raw='';for await(const x of req){raw+=x;if(raw.length>20000)fail(413,'Yêu cầu quá lớn.');}
   let b;try{b=JSON.parse(raw||'{}');}catch{fail(400,'JSON không hợp lệ.');}
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
   const u=await getUser(req);if(!u)fail(401,'Vui lòng đăng nhập.');if(req.method!=='GET')fail(405,'Mốc này chỉ hỗ trợ đọc dữ liệu sau đăng nhập.');
   if(url.pathname==='/api/me')return send(200,u);
   if(url.pathname==='/api/state')return send(200,await state(u));
   if(url.pathname==='/api/admin/users'){requireRoles(u,'ADMIN');return send(200,await jsonQuery('SELECT u.UserId,u.Name,u.Email,u.Active,JSON_QUERY((SELECT r.Code FROM UserRoles ur JOIN Roles r ON r.RoleId=ur.RoleId WHERE ur.UserId=u.UserId FOR JSON PATH)) AS roles FROM Users u FOR JSON PATH'));}
   if(url.pathname.startsWith('/api/departments/')){const role=url.pathname.slice('/api/departments/'.length);if(!Object.hasOwn(roles,role))fail(404,'Bộ phận không tồn tại.');requireRoles(u,role);return send(200,{role,name:roles[role],message:'Quyền truy cập đã được kiểm tra tại backend.'});}
   if(/^\/api\/bookings\/[^/]+$/.test(url.pathname)){requireRoles(u,'PASSENGER','FINANCE');const rows=await jsonQuery(bookingQuery(u,url.pathname.split('/').pop())+' FOR JSON PATH');if(!rows.length)fail(403,'Không có quyền xem đặt chỗ này hoặc đặt chỗ không tồn tại.');return send(200,rows[0]);}
   fail(404,'API chưa được triển khai trong tuần 1.');
  }
  if(req.method!=='GET')fail(405,'Method không hỗ trợ.');
  const file=path.resolve(root,'.'+(url.pathname==='/'?'/index.html':decodeURIComponent(url.pathname)));
  if(!file.startsWith(root))fail(403,'Không được phép truy cập.');
  const data=await readFile(file);res.writeHead(200,{'Content-Type':({'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8'})[path.extname(file)]||'application/octet-stream','Cache-Control':'no-cache','X-Content-Type-Options':'nosniff'});res.end(data);
 }catch(e){const status=e.status||(e.code==='ENOENT'?404:503);send(status,{error:status===503?'Chưa kết nối được database. Kiểm tra SQL Server và chạy npm run setup.':e.message});}
});
await query('SELECT TOP(1) PasswordHash,Active FROM Users;');
server.listen(port,'127.0.0.1',()=>console.log(`Aurora Week 1: http://localhost:${port}`));
setInterval(()=>{for(const [id,s] of sessions)if(s.expires<=Date.now())sessions.delete(id);for(const [key,t] of attempts)if(Date.now()-t.time>=60000)attempts.delete(key);},60000).unref();
