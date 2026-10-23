import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {randomBytes,randomUUID} from 'node:crypto';
import net from 'node:net';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../',import.meta.url));
const database=`CruiseWeek1PosTest_${randomBytes(5).toString('hex')}`;
const sqlcmd=process.env.SQLCMD_PATH||'sqlcmd',sqlServer=process.env.SQL_SERVER||'.';
const runSql=(db,statement)=>{
 const result=spawnSync(sqlcmd,['-S',sqlServer,'-d',db,'-E','-C','-I','-b','-l','10','-Q',statement],{encoding:'utf8',windowsHide:true,env:process.env});
 if(result.error||result.status!==0)throw Error(result.error?.message||result.stderr||result.stdout);
 return result.stdout.trim();
};
const dropDatabase=()=>runSql('master',`IF DB_ID(N'${database}') IS NOT NULL BEGIN ALTER DATABASE [${database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [${database}]; END;`);
const check=(name,fn)=>fn().then(()=>console.log('PASS '+name));
async function startServer(port){
 const child=spawn(process.execPath,['server.mjs'],{cwd:root,env:{...process.env,SQL_DATABASE:database,PORT:String(port)},windowsHide:true});
 let output='',errors='';child.testErrors=()=>errors;
 await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{child.kill();reject(Error('Server không khởi động: '+errors));},20000);child.stdout.on('data',chunk=>{output+=chunk;if(output.includes(`http://localhost:${port}`)){clearTimeout(timer);resolve();}});child.stderr.on('data',chunk=>errors+=chunk);child.on('error',reject);child.on('exit',code=>{if(code)reject(Error(errors||output));});});
 return child;
}
async function call(base,path,body,cookie){
 const response=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{...(body===undefined?{}:{'Content-Type':'application/json'}),...(cookie?{Cookie:cookie}:{})},body:body===undefined?undefined:JSON.stringify(body)});
 return{status:response.status,data:await response.json(),cookie:response.headers.get('set-cookie')?.split(';')[0]};
}

let server;
try{
 const setup=spawnSync(process.execPath,['scripts/setup.mjs'],{cwd:root,encoding:'utf8',windowsHide:true,env:{...process.env,SQL_DATABASE:database}});
 if(setup.error||setup.status!==0)throw Error(setup.error?.message||setup.stderr||setup.stdout);
 // Mô phỏng database từ bản trước: UNIQUE(RegistrationId) chặn nhiều dòng NULL của POS.
 runSql(database,'DROP INDEX UX_Transactions_RegistrationId ON dbo.Transactions; ALTER TABLE dbo.Transactions ADD CONSTRAINT UQ_Transactions_RegistrationId UNIQUE(RegistrationId);');
 const upgrade=spawnSync(process.execPath,['scripts/setup.mjs'],{cwd:root,encoding:'utf8',windowsHide:true,env:{...process.env,SQL_DATABASE:database}});
 if(upgrade.error||upgrade.status!==0)throw Error(upgrade.error?.message||upgrade.stderr||upgrade.stdout);
 process.env.SQL_DATABASE=database;
 const {jsonQuery}=await import('../src/db.mjs?pos-sync='+Date.now());
 const socket=net.createServer();await new Promise(resolve=>socket.listen(0,'127.0.0.1',resolve));const port=socket.address().port;await new Promise(resolve=>socket.close(resolve));
 server=await startServer(port);const base=`http://127.0.0.1:${port}`;
 const pos=await call(base,'/api/login',{email:'pos@demo.local',password:'Aurora123!'});assert.equal(pos.status,200);
 const guest=await call(base,'/api/login',{email:'guest10@demo.local',password:'Aurora123!'});assert.equal(guest.status,200);
 const payload={clientId:randomUUID(),code:'AURORA-010',serviceId:1,quantity:2,deviceId:1};let first;
 await check('POS đồng bộ giao dịch, tự tính giá và trả biên nhận SQL',async()=>{first=await call(base,'/api/pos/sync',payload,pos.cookie);assert.equal(first.status,200,JSON.stringify(first.data));assert.equal(Number(first.data.transaction.Amount),70000);assert.equal(first.data.transaction.ClientId.toLowerCase(),payload.clientId.toLowerCase());assert.equal(first.data.receipt.ClientId.toLowerCase(),payload.clientId.toLowerCase());assert.equal(first.data.receipt.TransactionId,first.data.transaction.TransactionId);});
 await check('Gửi lại cùng UUID và nội dung không tạo giao dịch hoặc biên nhận trùng',async()=>{const replay=await call(base,'/api/pos/sync',payload,pos.cookie);assert.equal(replay.status,200,JSON.stringify(replay.data));assert.equal(replay.data.transaction.TransactionId,first.data.transaction.TransactionId);assert.equal(replay.data.receipt.ReceiptId,first.data.receipt.ReceiptId);const rows=await jsonQuery(`SELECT (SELECT COUNT(*) FROM dbo.Transactions WHERE ClientId=CONVERT(uniqueidentifier,N'${payload.clientId}')) AS Transactions,(SELECT COUNT(*) FROM dbo.POSReceipts WHERE ClientId=CONVERT(uniqueidentifier,N'${payload.clientId}')) AS Receipts FOR JSON PATH`);assert.equal(rows[0].Transactions,1);assert.equal(rows[0].Receipts,1);});
 await check('Hai request đồng thời cùng UUID chỉ ghi một giao dịch và biên nhận',async()=>{const concurrent={...payload,clientId:randomUUID(),code:'AURORA-010',quantity:1};const replies=await Promise.all([call(base,'/api/pos/sync',concurrent,pos.cookie),call(base,'/api/pos/sync',concurrent,pos.cookie)]);assert(replies.every(x=>x.status===200),JSON.stringify({replies,errors:server.testErrors()}));assert.equal(replies[0].data.transaction.TransactionId,replies[1].data.transaction.TransactionId);assert.equal(replies[0].data.receipt.ReceiptId,replies[1].data.receipt.ReceiptId);const rows=await jsonQuery(`SELECT (SELECT COUNT(*) FROM dbo.Transactions WHERE ClientId=CONVERT(uniqueidentifier,N'${concurrent.clientId}')) AS Transactions,(SELECT COUNT(*) FROM dbo.POSReceipts WHERE ClientId=CONVERT(uniqueidentifier,N'${concurrent.clientId}')) AS Receipts FOR JSON PATH`);assert.equal(rows[0].Transactions,1);assert.equal(rows[0].Receipts,1);});
 await check('Từ chối dùng lại UUID với payload khác',async()=>{const changed=await call(base,'/api/pos/sync',{...payload,quantity:3},pos.cookie);assert.equal(changed.status,422);});
 await check('Từ chối mã khách không hợp lệ',async()=>{const invalid=await call(base,'/api/pos/sync',{...payload,clientId:randomUUID(),code:'INVALID-CODE'},pos.cookie);assert.equal(invalid.status,422);});
 await check('Không cho hành khách gọi API POS',async()=>{const denied=await call(base,'/api/pos/sync',{...payload,clientId:randomUUID()},guest.cookie);assert.equal(denied.status,403);});
 await check('POS tra cứu được các biên nhận của mình',async()=>{const receipts=await call(base,'/api/pos/receipts',undefined,pos.cookie);assert.equal(receipts.status,200);assert.equal(receipts.data.length,2);assert(receipts.data.some(r=>r.ReceiptId===first.data.receipt.ReceiptId));});
 await check('Hành khách không được xem biên nhận POS',async()=>{const denied=await call(base,'/api/pos/receipts',undefined,guest.cookie);assert.equal(denied.status,403);});
 console.log('POS receipt integration checks passed.');
}finally{
 if(server){server.kill();await new Promise(resolve=>server.once('exit',resolve));}
 try{dropDatabase();console.log('Database kiểm thử tạm đã được xóa.');}catch(error){console.error('Không xóa được database kiểm thử:',error.message);}
}
