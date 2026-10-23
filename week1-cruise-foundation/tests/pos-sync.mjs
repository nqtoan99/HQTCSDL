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
 process.env.SQL_DATABASE=database;
 const {jsonQuery}=await import('../src/db.mjs?pos-sync='+Date.now());
 const socket=net.createServer();await new Promise(resolve=>socket.listen(0,'127.0.0.1',resolve));const port=socket.address().port;await new Promise(resolve=>socket.close(resolve));
 server=await startServer(port);const base=`http://127.0.0.1:${port}`;
 const pos=await call(base,'/api/login',{email:'pos@demo.local',password:'Aurora123!'});assert.equal(pos.status,200);
 const guest=await call(base,'/api/login',{email:'guest10@demo.local',password:'Aurora123!'});assert.equal(guest.status,200);
 const payload={clientId:randomUUID(),code:'AURORA-010',serviceId:1,quantity:2,deviceId:1};let first;
 await check('POS đồng bộ giao dịch và SQL tự tính giá',async()=>{first=await call(base,'/api/pos/sync',payload,pos.cookie);assert.equal(first.status,200,JSON.stringify(first.data));assert.equal(Number(first.data.transaction.Amount),70000);assert.equal(first.data.transaction.ClientId.toLowerCase(),payload.clientId.toLowerCase());});
 await check('Gửi lại cùng UUID và nội dung không tạo giao dịch thứ hai',async()=>{const replay=await call(base,'/api/pos/sync',payload,pos.cookie);assert.equal(replay.status,200,JSON.stringify(replay.data));assert.equal(replay.data.transaction.TransactionId,first.data.transaction.TransactionId);const rows=await jsonQuery(`SELECT COUNT(*) AS Total FROM dbo.Transactions WHERE ClientId=CONVERT(uniqueidentifier,N'${payload.clientId}') FOR JSON PATH`);assert.equal(rows[0].Total,1);});
 await check('Hai request đồng thời cùng UUID chỉ ghi một lần',async()=>{const concurrent={...payload,clientId:randomUUID(),code:'AURORA-010',quantity:1};const replies=await Promise.all([call(base,'/api/pos/sync',concurrent,pos.cookie),call(base,'/api/pos/sync',concurrent,pos.cookie)]);assert(replies.every(x=>x.status===200),JSON.stringify({replies,errors:server.testErrors()}));assert.equal(replies[0].data.transaction.TransactionId,replies[1].data.transaction.TransactionId);const rows=await jsonQuery(`SELECT COUNT(*) AS Total FROM dbo.Transactions WHERE ClientId=CONVERT(uniqueidentifier,N'${concurrent.clientId}') FOR JSON PATH`);assert.equal(rows[0].Total,1);});
 await check('Từ chối dùng lại UUID với payload khác',async()=>{const changed=await call(base,'/api/pos/sync',{...payload,quantity:3},pos.cookie);assert.equal(changed.status,422);});
 await check('Từ chối mã khách không hợp lệ',async()=>{const invalid=await call(base,'/api/pos/sync',{...payload,clientId:randomUUID(),code:'INVALID-CODE'},pos.cookie);assert.equal(invalid.status,422);});
 await check('Không cho hành khách gọi API POS',async()=>{const denied=await call(base,'/api/pos/sync',{...payload,clientId:randomUUID()},guest.cookie);assert.equal(denied.status,403);});
 console.log('POS sync integration checks passed.');
}finally{
 if(server){server.kill();await new Promise(resolve=>server.once('exit',resolve));}
 try{dropDatabase();console.log('Database kiểm thử tạm đã được xóa.');}catch(error){console.error('Không xóa được database kiểm thử:',error.message);}
}
