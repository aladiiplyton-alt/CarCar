import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const project=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const source=fs.readFileSync(path.join(project,'tests/profile-crypto.ps1'),'utf8');
const quote=value=>"'"+value.replaceAll("'","''")+"'";
const result=spawnSync('powershell.exe',['-NoProfile','-Command',`& {${source}} -ProjectRoot ${quote(project)}`],{windowsHide:true,stdio:'inherit'});
process.exitCode=result.status??1;
