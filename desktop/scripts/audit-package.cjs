// Inspect our allowlisted app and resources; never print matched secret values.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
(async()=>{
 const {extractAll}=await import('@electron/asar');
 const resources=path.resolve(process.argv[2]);
 const temp=fs.mkdtempSync(path.join(os.tmpdir(),'chan-package-audit-'));
 try{
  extractAll(path.join(resources,'app.asar'),temp);
  const roots=[temp,path.join(resources,'assets'),path.join(resources,'integrations')];let files=0;const bad=[];
  function scan(root,relative=''){
   for(const item of fs.readdirSync(path.join(root,relative),{withFileTypes:true})){
    const name=path.join(relative,item.name),full=path.join(root,name);
    if(item.isDirectory()){if(['node_modules','.git','.build','dist'].includes(item.name))bad.push([name,'unexpected directory']);scan(root,name);continue;}
    files++;
    if(/\.(pdb|map|log|key|pem|db|sqlite|keychain)$/i.test(name)||item.name.startsWith('.env'))bad.push([name,'private or development artifact']);
    const bytes=fs.readFileSync(full);
    for(const text of [bytes.toString('utf8'),bytes.toString('utf16le')]){
     if(/(?:\/Users\/|C:\\Users\\)(?!runner\b)[A-Za-z0-9_.-]+[\\/]/i.test(text))bad.push([name,'personal build path']);
     if(/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|sk-or-v1-[a-f0-9]{32,}|gh[pousr]_[A-Za-z0-9]{30,}/.test(text))bad.push([name,'credential pattern']);
    }
   }
  }
  roots.forEach(root=>scan(root));
  if(bad.length){console.error(JSON.stringify(bad));process.exitCode=1;}else console.log(`PASS: ${files} packaged project files; no private configs, source maps, PDBs, personal build paths or credential patterns`);
 }finally{fs.rmSync(temp,{recursive:true,force:true});}
})().catch(error=>{console.error(error.message);process.exitCode=1;});
