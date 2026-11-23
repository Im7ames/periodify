import {readFile,writeFile,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
const tag=process.env.TAG;
if(!/^v\d+\.\d+\.\d+$/.test(tag??''))throw Error('Invalid release tag');
const repo=process.env.GITHUB_REPOSITORY;
const expected={'Android':'periodify-android.apk','Wear OS':'periodify-wear-os.apk','Windows x64':'periodify-windows.exe','macOS':'periodify-macos.dmg','Linux x64':'periodify-linux.deb','Web':'periodify-web.zip'};
const files=await readdir('artifacts');
if(!files.includes(expected.Web))throw Error('Missing checked web build');
if(files.includes(expected['Linux x64']) && !['periodify-linux.deb.asc','linux-signing-key.asc'].every(name=>files.includes(name)))throw Error('Missing Linux signing assets');
if(files.includes(expected.Android)!==files.includes(expected['Wear OS']))throw Error('Phone and watch APKs must be released together');
const assets=[];
for(const name of files.sort()){
 const data=await readFile(`artifacts/${name}`);
 assets.push({name,sha256:createHash('sha256').update(data).digest('hex'),size:data.length,url:`https://github.com/${repo}/releases/download/${tag}/${name}`});
}
await writeFile('artifacts/SHA256SUMS.txt',assets.map(a=>`${a.sha256}  ${a.name}`).join('\n')+'\n');
await writeFile('artifacts/updates.json',JSON.stringify({schema:1,version:tag.slice(1),releaseUrl:`https://github.com/${repo}/releases/tag/${tag}`,assets},null,2));
const gh=(args)=>execFileSync('gh',args,{encoding:'utf8'});
gh(['release','upload',tag,...(await readdir('artifacts')).map(f=>`artifacts/${f}`),'--clobber']);
const release=JSON.parse(gh(['release','view',tag,'--json','assets,body']));
for(const file of await readdir('artifacts'))if(!release.assets.some(a=>a.name===file))throw Error(`Upload missing: ${file}`);
const runUrl=`https://github.com/${repo}/actions/runs/${process.env.GITHUB_RUN_ID}`;
const table='<!-- downloads -->\n| Platform | Download |\n| --- | --- |\n'+Object.entries(expected).map(([platform,name])=>files.includes(name)?`| ${platform} | [${name}](https://github.com/${repo}/releases/download/${tag}/${name}) |`:`| ${platform} | Unavailable · [build status](${runUrl}) |`).join('\n')+'\n\nWindows and macOS downloads require trusted signing. See [release setup](https://github.com/'+repo+'/blob/'+tag+'/docs/RELEASING.md).\n\nChecksums: [SHA256SUMS.txt](https://github.com/'+repo+'/releases/download/'+tag+'/SHA256SUMS.txt). Update manifest: [updates.json](https://github.com/'+repo+'/releases/download/'+tag+'/updates.json).\n<!-- /downloads -->';
const body=release.body.replace(/<!-- downloads -->[\s\S]*?<!-- \/downloads -->/g,'').trim()+'\n\n'+table;
await writeFile('release-body.md',body);
gh(['release','edit',tag,'--notes-file','release-body.md']);
const verified=JSON.parse(gh(['release','view',tag,'--json','assets,body']));
if(!verified.body.includes(table))throw Error('Download table verification failed');
for(const asset of assets){const response=await fetch(asset.url);if(!response.ok)throw Error(`Download failed: ${asset.name}`);const bytes=Buffer.from(await response.arrayBuffer());if(createHash('sha256').update(bytes).digest('hex')!==asset.sha256)throw Error(`Checksum mismatch: ${asset.name}`);}
console.log('Release assets, download table, and downloaded checksums verified.');
