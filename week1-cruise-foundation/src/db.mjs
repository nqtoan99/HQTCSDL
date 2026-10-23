// Tách từ cruise-sql/src/db.mjs: sqlcmd, JSON Unicode và mật khẩu scrypt.
import {spawn} from 'node:child_process';
import {randomBytes,scryptSync,timingSafeEqual} from 'node:crypto';
export const database=process.env.SQL_DATABASE||'CruiseWeek1';
if(!/^[A-Za-z][A-Za-z0-9_]{0,100}$/.test(database))throw Error('Tên SQL_DATABASE không hợp lệ.');
export const literal=v=>v===null?'NULL':typeof v==='number'&&Number.isFinite(v)?String(v):`N'${String(v).replaceAll("'","''")}'`;
export function hashPassword(password){const salt=randomBytes(16).toString('hex');return salt+':'+scryptSync(password,salt,64).toString('hex');}
export function verifyPassword(password,stored){if(typeof stored!=='string'||!/^[a-f0-9]{32}:[a-f0-9]{128}$/.test(stored))return false;const [salt,hash]=stored.split(':');return timingSafeEqual(scryptSync(password,salt,64),Buffer.from(hash,'hex'));}
export function query(sql){return new Promise((resolve,reject)=>{
 if(sql.length>28000)return reject(Error('Yêu cầu SQL quá lớn.'));
 const p=spawn(process.env.SQLCMD_PATH||'sqlcmd',['-S',process.env.SQL_SERVER||'.','-d',database,'-E','-C','-I','-b','-l','5','-f','65001','-y','8000','-w','65535','-h','-1','-Q','SET NOCOUNT ON; '+sql],{windowsHide:true});
 const out=[],err=[],timer=setTimeout(()=>{p.kill();reject(Error('SQL Server quá thời gian chờ.'));},20000);
 p.stdout.on('data',v=>out.push(v));p.stderr.on('data',v=>err.push(v));p.on('error',e=>{clearTimeout(timer);reject(e);});
 p.on('close',code=>{clearTimeout(timer);const text=Buffer.concat(out).toString('utf8').replace(/^\uFEFF/,'').trim();if(code)reject(Error(Buffer.concat(err).toString('utf8').trim()||text));else resolve(text);});
});}
// JSON truyền qua hex UTF-16 để không mất dấu tiếng Việt trên Windows console.
export async function jsonQuery(sql){
 const raw=(await query(`;WITH Payload AS (SELECT CONVERT(varchar(max),CONVERT(varbinary(max),(${sql})),2) AS Hex), Chunks AS (SELECT 1 AS StartAt UNION ALL SELECT c.StartAt+4000 FROM Chunks c CROSS JOIN Payload p WHERE c.StartAt+4000<=LEN(p.Hex)) SELECT SUBSTRING(p.Hex,c.StartAt,4000) FROM Payload p CROSS JOIN Chunks c ORDER BY c.StartAt OPTION(MAXRECURSION 0);`)).replace(/\s/g,'');
 return JSON.parse(Buffer.from(raw,'hex').toString('utf16le')||'[]');
}
