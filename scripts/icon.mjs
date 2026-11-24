// Small original CarCar mark; deterministic ICO generation, no external assets.
import fs from 'node:fs';
const n=64,row=n*4,pixels=Buffer.alloc(row*n);for(let y=0;y<n;y++)for(let x=0;x<n;x++){
 let rgb=[39,45,35];const dx=Math.abs(x-31.5),dy=Math.abs(y-31.5);if((dx<5&&dy<22-dx*2.7)||(dy<5&&dx<22-dy*2.7))rgb=[211,226,190];
 const i=((n-1-y)*n+x)*4;pixels[i]=rgb[2];pixels[i+1]=rgb[1];pixels[i+2]=rgb[0];pixels[i+3]=255;
}const dib=Buffer.alloc(40);dib.writeUInt32LE(40);dib.writeInt32LE(n,4);dib.writeInt32LE(n*2,8);dib.writeUInt16LE(1,12);dib.writeUInt16LE(32,14);dib.writeUInt32LE(pixels.length,20);
const data=Buffer.concat([dib,pixels,Buffer.alloc(n*n/8)]);const head=Buffer.alloc(22);head.writeUInt16LE(1,2);head.writeUInt16LE(1,4);head[6]=n;head[7]=n;head.writeUInt16LE(1,10);head.writeUInt16LE(32,12);head.writeUInt32LE(data.length,14);head.writeUInt32LE(22,18);
fs.mkdirSync(new URL('../src-tauri/icons/',import.meta.url),{recursive:true});fs.writeFileSync(new URL('../src-tauri/icons/icon.ico',import.meta.url),Buffer.concat([head,data]));
