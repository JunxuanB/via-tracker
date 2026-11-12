// VIA data contract is observational. This fixture does not assert operator guarantees.
const http=require('http');
const fs=require('fs');
const path=require('path');
const sample=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../../../contracts/fixtures/via-synthetic.json'),'utf8'));
http.createServer(async(req,res)=>{
  const url=new URL(req.url,'http://fixture');
  res.setHeader('content-type','application/json');
  if(url.pathname==='/control') {await pm.state.set('via.mode',url.searchParams.get('mode')||'healthy');return res.end('{}');}
  if(url.pathname!=='/data/allData.json'){res.statusCode=501;return res.end('{"error":"unmodeled_endpoint"}');}
  const mode=await pm.state.get('via.mode');
  if(mode==='failure'){res.statusCode=503;return res.end('{"error":"upstream_unavailable"}');}
  if(mode==='empty')return res.end('{}');
  return res.end(JSON.stringify(sample));
}).listen(process.env.PORT);
