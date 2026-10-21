import urllib.request,json,pathlib,concurrent.futures,subprocess
root=pathlib.Path.home()/'Library/Application Support/Local Voice/asr-models'
repos={'Qwen3-ASR-1.7B-8bit':'a8379a2e2f9e313c9292cdf1af4055ab56d50d55','Qwen3-ASR-0.6B-8bit':'89e96d92ba34aca20b3e29fb10cc284097d1219f'}
def download(item):
 repo,rev,name=item
 p=root/repo/name;p.parent.mkdir(parents=True,exist_ok=True)
 if p.exists():return
 subprocess.run(['curl','-sSL','--fail','--retry','3','-o',str(p)+'.part','https://huggingface.co/mlx-community/'+repo+'/resolve/'+rev+'/'+name],check=True)
 pathlib.Path(str(p)+'.part').replace(p)
 print(repo,name,p.stat().st_size,flush=True)
jobs=[]
for repo,rev in repos.items():
 meta=json.load(urllib.request.urlopen('https://huggingface.co/api/models/mlx-community/'+repo))
 jobs += [(repo,rev,x['rfilename']) for x in meta['siblings'] if not x['rfilename'].startswith('.')]
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:list(pool.map(download,jobs))
