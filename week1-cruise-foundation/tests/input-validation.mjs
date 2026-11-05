import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import net from 'node:net';
import {fileURLToPath} from 'node:url';
import {InputValidationError,parseAmount,parseBoolean,parseId,parseOptionalId,parseText,parseWhole} from '../src/validation.mjs';
import {readJsonBody} from '../src/json-body.mjs';

const root=fileURLToPath(new URL('../',import.meta.url));
const database=`CruiseWeek1Input_${randomBytes(5).toString('hex')}`;
const sqlcmd=process.env.SQLCMD_PATH||'sqlcmd',sqlServer=process.env.SQL_SERVER||'.';
const runSql=(db,statement)=>{
 const result=spawnSync(sqlcmd,['-S',sqlServer,'-d',db,'-E','-C','-I','-b','-l','10','-f','65001','-Q',statement],{encoding:'utf8',windowsHide:true,env:process.env});
 if(result.error||result.status!==0)throw Error(result.error?.message||result.stderr||result.stdout);
 return result.stdout.trim();
};
const dropDatabase=()=>runSql('master',`IF DB_ID(N'${database}') IS NOT NULL BEGIN ALTER DATABASE [${database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [${database}]; END;`);
const check=(name,fn)=>{fn();console.log('PASS '+name);};
const checkAsync=async(name,fn)=>{await fn();console.log('PASS '+name);};
async function startServer(port){
 const child=spawn(process.execPath,['server.mjs'],{cwd:root,env:{...process.env,SQL_DATABASE:database,PORT:String(port)},windowsHide:true});
 let out='',errors='';
 await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{child.kill();reject(Error('API khởi động thất bại: '+errors));},20000);child.stdout.on('data',chunk=>{out+=chunk;if(out.includes(`http://localhost:${port}`)){clearTimeout(timer);resolve();}});child.stderr.on('data',chunk=>errors+=chunk);child.on('error',reject);child.on('exit',code=>{if(code)reject(Error(errors||out));});});
 return child;
}
async function call(base,path,body,cookie){
 const response=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{...(body===undefined?{}:{'Content-Type':'application/json'}),...(cookie?{Cookie:cookie}:{})},body:body===undefined?undefined:JSON.stringify(body)});
 return{status:response.status,data:await response.json(),cookie:response.headers.get('set-cookie')?.split(';')[0]};
}

check('ID chỉ nhận số nguyên dương an toàn',()=>{
 assert.equal(parseId(7),7);assert.equal(parseId('7'),7);
 for(const value of [true,false,null,0,-1,1.5,'',' 7','1e0','07',Number.MAX_SAFE_INTEGER+1])assert.throws(()=>parseId(value),InputValidationError);
});
check('ID tùy chọn chấp nhận 0 nhưng từ chối boolean và chuỗi không chuẩn',()=>{
 for(const value of [undefined,null,'',0,'0'])assert.equal(parseOptionalId(value),0);
 assert.throws(()=>parseOptionalId(true),InputValidationError);assert.throws(()=>parseOptionalId(' 0'),InputValidationError);assert.throws(()=>parseOptionalId(-1),InputValidationError);
});
check('Boolean chỉ nhận JSON true hoặc false',()=>{
 assert.equal(parseBoolean(true),true);assert.equal(parseBoolean(false),false);
 for(const value of [0,1,'true','false',null,undefined,{}])assert.throws(()=>parseBoolean(value),InputValidationError);
});
check('Các số nguyên và tiền từ chối kiểu boolean',()=>{
 assert.equal(parseWhole(3,1,10),3);assert.equal(parseAmount(12.5),12.5);
 assert.throws(()=>parseWhole(true,0,10),InputValidationError);assert.throws(()=>parseAmount(false),InputValidationError);
});
check('Chuỗi Unicode hợp lệ được giữ nguyên và surrogate lỗi bị từ chối',()=>{
 const value='Cảng Đà Nẵng – Vịnh Hạ Long';assert.equal(parseText(value,100),value);
 assert.throws(()=>parseText('\ud800',10),InputValidationError);assert.throws(()=>parseText('a\0b',10),InputValidationError);
});
await checkAsync('JSON UTF-8 vẫn nguyên vẹn khi byte ký tự bị chia thành nhiều chunk',async()=>{
 const expected={name:'Cảng Đà Nẵng – Vịnh Hạ Long'};const bytes=Buffer.from(JSON.stringify(expected),'utf8');
 const request=(async function*(){for(const byte of bytes)yield Buffer.from([byte]);})();
 assert.deepEqual(await readJsonBody(request),expected);
});
await checkAsync('JSON UTF-8 sai mã hóa, object sai dạng và body quá lớn bị từ chối',async()=>{
 await assert.rejects(readJsonBody((async function*(){yield Buffer.from([0x7b,0x22,0x78,0x22,0x3a,0x22,0xc3,0x28,0x22,0x7d]);})()),e=>e.status===400);
 await assert.rejects(readJsonBody((async function*(){yield Buffer.from('[1,2]');})()),e=>e.status===400);
 await assert.rejects(readJsonBody((async function*(){yield Buffer.alloc(20001,0x20);})()),e=>e.status===413);
});

let server;
try{
 dropDatabase();
 const setup=spawnSync(process.execPath,['scripts/setup.mjs'],{cwd:root,encoding:'utf8',windowsHide:true,env:{...process.env,SQL_DATABASE:database}});
 if(setup.error||setup.status!==0)throw Error(setup.error?.message||setup.stderr||setup.stdout);
 process.env.SQL_DATABASE=database;
 const {jsonQuery,literal,query}=await import(`../src/db.mjs?input-validation=${Date.now()}`);
 await checkAsync('SQL literal escape dấu nháy và giữ Unicode tiếng Việt',async()=>{
  const name="Bến cảng 'Huế' – Đà Nẵng";
  assert.equal(literal(name),"N'Bến cảng ''Huế'' – Đà Nẵng'");
  await query(`INSERT dbo.Ports(Name) VALUES(${literal(name)});`);
  const saved=(await jsonQuery(`SELECT Name FROM dbo.Ports WHERE Name=${literal(name)} FOR JSON PATH`))[0];
  assert.equal(saved.Name,name);
  assert.throws(()=>literal('\ud800'),InputValidationError);
 });

 const socket=net.createServer();await new Promise(resolve=>socket.listen(0,'127.0.0.1',resolve));const port=socket.address().port;await new Promise(resolve=>socket.close(resolve));
 server=await startServer(port);const base=`http://127.0.0.1:${port}`;
 const login=async email=>{const response=await call(base,'/api/login',{email,password:'Aurora123!'});assert.equal(response.status,200,JSON.stringify(response.data));return response.cookie;};
 const admin=await login('admin@demo.local'),finance=await login('finance@demo.local'),itinerary=await login('itinerary@demo.local'),shore=await login('shore@demo.local');
 await checkAsync('API từ chối ID boolean và ID ở dạng mũ số',async()=>{
  assert.equal((await call(base,'/api/admin/catalogs',{entity:'service',catalogId:true,name:'Sai kiểu',price:100},admin)).status,400);
  assert.equal((await call(base,'/api/finance/reconcile',{transactionId:'1e0'},finance)).status,400);
  assert.equal((await call(base,'/api/itinerary/ports',{portId:true,name:'Sai ID'},itinerary)).status,400);
 });
 await checkAsync('API từ chối boolean gửi dưới dạng chuỗi hoặc số',async()=>{
  assert.equal((await call(base,'/api/shore/providers',{name:'Sai boolean',active:'false'},shore)).status,400);
  assert.equal((await call(base,'/api/admin/identifiers/1/active',{active:1},admin)).status,400);
  assert.equal((await call(base,'/api/admin/package-services',{packageId:1,serviceId:1,included:'true'},admin)).status,400);
 });
 await checkAsync('API ghi và đọc lại chính xác tên cảng tiếng Việt có dấu nháy',async()=>{
  const name="Cảng 'Đà Nẵng' – Vịnh Hạ Long";
  const response=await call(base,'/api/itinerary/ports',{name},itinerary);assert.equal(response.status,201,JSON.stringify(response.data));
  const saved=(await jsonQuery(`SELECT Name FROM dbo.Ports WHERE Name=${literal(name)} FOR JSON PATH`))[0];assert.equal(saved.Name,name);
 });
}finally{
 if(server){server.kill();await new Promise(resolve=>server.once('exit',resolve));}
 try{dropDatabase();console.log('Database kiểm thử tạm đã được xóa.');}catch(error){console.error('Không xóa được database kiểm thử:',error.message);}
}
