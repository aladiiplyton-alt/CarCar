import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
const project=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const counts={flaky:0,corrupt:0};
const server=http.createServer((req,res)=>{
  const route=new URL(req.url,'http://127.0.0.1').pathname;
  if(route==='/flaky'){counts.flaky++;if(counts.flaky<3){res.writeHead(503);res.end('retry')}else{res.end('abc')}}
  else if(route==='/corrupt'){counts.corrupt++;res.end('wrong')}
  else if(route==='/counts'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify(counts))}
  else {res.writeHead(404);res.end()}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const port=server.address().port;
const source=fs.readFileSync(path.join(project,'tests/bootstrap-retry.ps1'),'utf8');
const quote=value=>"'"+value.replaceAll("'","''")+"'";
const command=`& { ${source} } -BaseUrl 'http://127.0.0.1:${port}' -ProjectRoot ${quote(project)}`;
const child=spawn('powershell.exe',['-NoProfile','-Command',command],{windowsHide:true,stdio:'inherit'});
child.on('error',error=>{console.error(error.message);server.close();process.exitCode=1});
child.on('exit',code=>{server.close();process.exitCode=code??1});
