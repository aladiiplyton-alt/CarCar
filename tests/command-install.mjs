import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const project=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const source=fs.readFileSync(path.join(project,'tests/command-install.ps1'),'utf8');
const quoted="'"+project.replaceAll("'","''")+"'";
const child=spawnSync('powershell.exe',['-NoProfile','-Command',`& {${source}} -ProjectRoot ${quoted}`],{windowsHide:true,stdio:'inherit'});
process.exitCode=child.status??1;
