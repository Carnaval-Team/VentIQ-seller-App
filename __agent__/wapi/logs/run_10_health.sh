set -u
NODE=/usr/local/bin/node
for p in /api/health /api/health/ready /api/infra/health; do
  echo "===== $p"
  docker exec openwa-api "$NODE" -e "
const t=Date.now();
fetch('http://127.0.0.1:2785'+process.argv[1]).then(async r=>{
  const b=await r.text();
  console.log('HTTP',r.status,'in',Date.now()-t,'ms');
  console.log(b.slice(0,1800));
}).catch(e=>console.log('ERR',e.message));
" "$p"
done
