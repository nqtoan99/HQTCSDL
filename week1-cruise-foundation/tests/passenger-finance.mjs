import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import net from 'node:net';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../',import.meta.url));
const database=`CruiseWeek1FinanceTest_${randomBytes(5).toString('hex')}`;
const sqlcmd=process.env.SQLCMD_PATH||'sqlcmd',sqlServer=process.env.SQL_SERVER||'.';
const runSql=(db,statement)=>{const result=spawnSync(sqlcmd,['-S',sqlServer,'-d',db,'-E','-C','-I','-b','-l','10','-Q',statement],{encoding:'utf8',windowsHide:true,env:process.env});if(result.error||result.status!==0)throw Error(result.error?.message||result.stderr||result.stdout);return result.stdout.trim();};
const dropDatabase=()=>runSql('master',`IF DB_ID(N'${database}') IS NOT NULL BEGIN ALTER DATABASE [${database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [${database}]; END;`);
const check=async(name,action)=>{await action();console.log('PASS '+name);};
async function call(base,path,body,cookie){const response=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{...(body===undefined?{}:{'Content-Type':'application/json'}),...(cookie?{Cookie:cookie}:{})},body:body===undefined?undefined:JSON.stringify(body)});return{status:response.status,data:await response.json(),cookie:response.headers.get('set-cookie')?.split(';')[0]};}
async function startServer(port){const child=spawn(process.execPath,['server.mjs'],{cwd:root,env:{...process.env,SQL_DATABASE:database,PORT:String(port)},windowsHide:true});let output='',errors='';await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{child.kill();reject(Error('Server không khởi động: '+errors));},20000);child.stdout.on('data',chunk=>{output+=chunk;if(output.includes(`http://localhost:${port}`)){clearTimeout(timer);resolve();}});child.stderr.on('data',chunk=>errors+=chunk);child.on('error',reject);child.on('exit',code=>{if(code)reject(Error(errors||output));});});return child;}

let server;
try{
 const setup=spawnSync(process.execPath,['scripts/setup.mjs'],{cwd:root,encoding:'utf8',windowsHide:true,env:{...process.env,SQL_DATABASE:database}});
 if(setup.error||setup.status!==0)throw Error(setup.error?.message||setup.stderr||setup.stdout);
 runSql(database,'EXEC dbo.usp_Register @BookingId=1,@ActivityId=3,@ActorId=6;');
 process.env.SQL_DATABASE=database;
 const {jsonQuery}=await import('../src/db.mjs?finance='+Date.now());
 const socket=net.createServer();await new Promise(resolve=>socket.listen(0,'127.0.0.1',resolve));const port=socket.address().port;await new Promise(resolve=>socket.close(resolve));
 server=await startServer(port);const base=`http://127.0.0.1:${port}`;
 const passenger=await call(base,'/api/login',{email:'guest1@demo.local',password:'Aurora123!'});assert.equal(passenger.status,200);
 const other=await call(base,'/api/login',{email:'guest2@demo.local',password:'Aurora123!'});assert.equal(other.status,200);
 const finance=await call(base,'/api/login',{email:'finance@demo.local',password:'Aurora123!'});assert.equal(finance.status,200);
 const tx=(await jsonQuery('SELECT TransactionId FROM dbo.Transactions WHERE AccountId=1 FOR JSON PATH'))[0];
 let dispute;
 await check('Hành khách xem chi phí tạm theo booking của mình',async()=>{const result=await call(base,'/api/passenger/finance',undefined,passenger.cookie);assert.equal(result.status,200,JSON.stringify(result.data));assert.equal(result.data.accounts.length,1,JSON.stringify(result.data));assert.equal(Number(result.data.accounts[0].UnpaidAmount),250000,JSON.stringify(result.data.accounts[0]));assert.equal(result.data.transactions.length,1,JSON.stringify(result.data));assert.equal(result.data.transactions[0].TransactionId,tx.TransactionId);});
 await check('Không cho hành khách đọc tài chính người khác hoặc FINANCE dùng API riêng của khách',async()=>{assert.equal((await call(base,'/api/passenger/finance',undefined,other.cookie)).data.transactions.length,0);assert.equal((await call(base,'/api/passenger/finance',undefined,finance.cookie)).status,403);});
 await check('Từ chối tranh chấp giao dịch không thuộc khách',async()=>{const denied=await call(base,'/api/passenger/disputes',{transactionId:tx.TransactionId,reason:'Tôi không nhận được dịch vụ này.'},other.cookie);assert.equal(denied.status,422);});
 await check('Gửi tranh chấp hợp lệ và chặn lý do quá ngắn',async()=>{assert.equal((await call(base,'/api/passenger/disputes',{transactionId:tx.TransactionId,reason:'Sai số tiền dịch vụ.'},passenger.cookie)).status,201);const short=await call(base,'/api/passenger/disputes',{transactionId:tx.TransactionId,reason:'Sai'},passenger.cookie);assert.equal(short.status,400);dispute=(await jsonQuery(`SELECT DisputeId,Status FROM dbo.Disputes WHERE TransactionId=${tx.TransactionId} FOR JSON PATH`))[0];assert.equal(dispute.Status,'OPEN');});
 await check('Chặn chốt tài khoản khi tranh chấp còn mở',async()=>{let blocked=false;try{runSql(database,'EXEC dbo.usp_SettleAccount @AccountId=1,@ActorId=4,@Method=\'MOCK\';');}catch{blocked=true;}assert(blocked);});
 await check('Sau khi tài chính giải quyết, khách xem được hóa đơn và khoản đã thanh toán',async()=>{runSql(database,`EXEC sys.sp_set_session_context @key=N'ActorId',@value=4; UPDATE dbo.Disputes SET Status='RESOLVED',ResolvedAt=SYSUTCDATETIME(),ResolvedBy=4,Resolution=N'Đã xác minh và xử lý.' WHERE DisputeId=${dispute.DisputeId}; EXEC dbo.usp_SettleAccount @AccountId=1,@ActorId=4,@Method='MOCK';`);const result=await call(base,'/api/passenger/finance',undefined,passenger.cookie);assert.equal(result.status,200,JSON.stringify(result.data));assert.equal(result.data.invoices.length,1);assert.equal(Number(result.data.invoices[0].Total),250000);assert.equal(Number(result.data.invoices[0].PaidAmount),250000);assert.equal(result.data.transactions[0].disputes[0].Status,'RESOLVED');});
 console.log('Passenger finance integration checks passed.');
}finally{if(server){server.kill();await new Promise(resolve=>server.once('exit',resolve));}try{dropDatabase();console.log('Database kiểm thử tạm đã được xóa.');}catch(error){console.error('Không xóa được database kiểm thử:',error.message);}}
