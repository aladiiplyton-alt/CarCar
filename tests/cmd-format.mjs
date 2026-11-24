import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync,execFileSync} from 'node:child_process';

const project=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const starter=fs.readFileSync(path.join(project,'start.cmd'));
for(const relative of ['start.cmd','docs/c','docs/c2','docs/c3']){
  const bytes=fs.readFileSync(path.join(project,relative));
  assert(bytes.equals(starter),`${relative} differs from start.cmd`);
  assert([...bytes].every(b=>b<128),`${relative} must be ASCII without BOM`);
  assert(!bytes.toString('ascii').replaceAll('\r\n','').includes('\n'),`${relative} contains bare LF`);
  assert(!bytes.toString('ascii').replaceAll('\r\n','').includes('\r'),`${relative} contains bare CR`);
  if(fs.existsSync(path.join(project,'.git'))){
    assert(execFileSync('git',['show',`:${relative}`],{cwd:project}).equals(bytes),`Git normalized ${relative}; preserve CRLF with -text`);
  }
}
assert(!/^chcp\b/im.test(starter.toString('ascii')),'The starter must not change the console code page');

const tempRoot=path.resolve(os.tmpdir());
const folder=fs.mkdtempSync(path.join(tempRoot,'CarCar-CMD-проба '));
const windows=process.env.SystemRoot||'C:\\Windows';
const cmd64=path.join(windows,'System32/cmd.exe');
const cmd32=path.join(windows,'SysWOW64/cmd.exe');
const compiler=['Framework64','Framework'].map(v=>path.join(windows,`Microsoft.NET/${v}/v4.0.30319/csc.exe`)).find(p=>fs.existsSync(p));
assert(compiler,'This Windows test needs the system .NET Framework C# compiler');
const source=path.join(folder,'TestShell.cs');
const shim=path.join(folder,'powershell.exe');
fs.writeFileSync(source,'using System; using System.Runtime.InteropServices; class TestShell { [DllImport("kernel32.dll")] static extern uint GetConsoleOutputCP(); static int Main(string[] a) { Console.WriteLine("CARCAR_POWERSHELL_REACHED"); Console.WriteLine("CARCAR_TEST_CP="+GetConsoleOutputCP()); string code=Environment.GetEnvironmentVariable("CARCAR_TEST_EXIT_CODE"); return String.IsNullOrEmpty(code)?0:Int32.Parse(code); } }','ascii');
let originalCp=0;
try{
  const build=spawnSync(compiler,['/nologo','/target:exe',`/out:${shim}`,source],{windowsHide:true,encoding:'utf8'});
  assert.equal(build.status,0,build.stdout+build.stderr);
  const observed=spawnSync(shim,[],{windowsHide:true,encoding:'utf8'});
  originalCp=Number(/CARCAR_TEST_CP=(\d+)/.exec(observed.stdout)?.[1]);
  assert(originalCp>0,'Run npm run test:cmd in an interactive Windows terminal');
  let cases=0;
  for(const shell of [cmd64,cmd32].filter(p=>fs.existsSync(p))){
    for(const cp of [437,866,65001]){
      for(const code of [0,7]){
        const file=path.join(folder,'cc.cmd');
        fs.writeFileSync(file,starter);
        const env={...process.env,TEMP:folder,TMP:folder,PATH:folder+';'+process.env.PATH,CARCAR_TEST_EXIT_CODE:String(code)};
        const command=`chcp ${cp} >nul & call "${file}"`;
        const result=spawnSync(command,{shell,env,cwd:folder,windowsHide:true,encoding:'utf8',timeout:15000});
        assert.equal(result.status,code,result.stdout+result.stderr);
        assert(result.stdout.includes('CARCAR_POWERSHELL_REACHED'),result.stdout+result.stderr);
        assert(result.stdout.includes(`CARCAR_TEST_CP=${cp}`),'The starter changed or lost the console code page');
        assert(!fs.existsSync(file),'The temporary copy was not removed');
        assert(!result.stderr.trim(),result.stderr);
        cases++;
      }
    }
  }
  const temporary=path.join(folder,'cc.cmd');
  fs.writeFileSync(temporary,starter);
  const continued=spawnSync(`call "${temporary}" & echo CARCAR_CALLER_CONTINUES`,{shell:cmd64,cwd:folder,env:{...process.env,TEMP:folder,TMP:folder,PATH:folder+';'+process.env.PATH},windowsHide:true,encoding:'utf8',timeout:15000});
  assert.equal(continued.status,0,continued.stdout+continued.stderr);
  assert(continued.stdout.includes('CARCAR_CALLER_CONTINUES'),'The starter closed the calling CMD');
  assert(!fs.existsSync(temporary),'The temporary starter remains after returning to the caller');
  const saved=path.join(folder,'start.cmd');
  fs.writeFileSync(saved,starter);
  const result=spawnSync(`call "${saved}"`,{shell:cmd64,cwd:folder,env:{...process.env,TEMP:folder,TMP:folder,PATH:folder+';'+process.env.PATH},windowsHide:true,encoding:'utf8',timeout:15000});
  assert.equal(result.status,0,result.stdout+result.stderr);
  assert(fs.existsSync(saved),'A saved starter must not delete itself');
  console.log(`PASS: ASCII/CRLF and Git bytes; ${cases} CMD runs across code pages 437/866/65001, 32/64-bit shells, exit codes 0/7; Unicode paths; temporary cleanup; calling CMD continues; saved file retained.`);
} finally {
  if(originalCp>0)spawnSync(`chcp ${originalCp} >nul`,{shell:cmd64,windowsHide:true});
  const resolved=path.resolve(folder);
  assert(path.dirname(resolved)===tempRoot&&path.basename(resolved).startsWith('CarCar-CMD-'),'Unsafe test cleanup path');
  fs.rmSync(resolved,{recursive:true,force:true});
}
