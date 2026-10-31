const http=require('http');
http.createServer(async(req,res)=>{
  const url=new URL(req.url,'http://fixture');
  res.setHeader('content-type','application/json');
  if(url.pathname==='/control'){await pm.state.set('apns.mode',url.searchParams.get('mode')||'healthy');return res.end('{}');}
  if(url.pathname==='/deliveries'){return res.end(JSON.stringify(await pm.state.get('apns.deliveries')||[]));}
  if(req.method==='POST'&&url.pathname.startsWith('/3/device/')){
    const deliveries=await pm.state.get('apns.deliveries')||[];
    deliveries.push({topic:req.headers['apns-topic'],pushType:req.headers['apns-push-type'],payload:req.body});
    await pm.state.set('apns.deliveries',deliveries);
    const mode=await pm.state.get('apns.mode');
    if(mode==='failure'){res.statusCode=503;return res.end('{"reason":"ServiceUnavailable"}');}
    if(mode==='invalid'){res.statusCode=410;return res.end('{"reason":"Unregistered"}');}
    return res.end('{}');
  }
  res.statusCode=501;res.end('{"error":"unmodeled_endpoint"}');
}).listen(process.env.PORT);
