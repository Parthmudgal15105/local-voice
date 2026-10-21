"""Train a small candidate, never change the shipped base model."""
import os,sys,json,pathlib,time,random
os.environ['HF_HUB_OFFLINE']='1';os.environ['TRANSFORMERS_OFFLINE']='1';sys.dont_write_bytecode=True
from adapter import attach,prepare,loss
from mlx_audio.stt import load
import mlx.core as mx,mlx.nn as nn,mlx.optimizers as optim
from mlx.utils import tree_flatten
mx.set_memory_limit(6*1024**3);mx.set_cache_limit(256*1024**2)
root=pathlib.Path(sys.argv[1]);records=json.loads((root/'samples.json').read_text())
records=[r for r in records if r.get('confirmed') and 0<r['seconds']<=30 and (root/(r['id']+'.wav')).exists()]
if len(records)<10:raise RuntimeError('Confirm at least 10 recordings of 30 seconds or less before training. More varied recordings are better.')
random.Random(42).shuffle(records)
priority=set(sys.argv[2].split(',')) if len(sys.argv)>2 else set()
records=sorted(records,key=lambda r:r['id'] not in priority)[:125]
validation_pool=sorted(records,key=lambda r:r['id'] in priority)
heldout=validation_pool[:max(2,len(records)//5)]
heldout_ids={r['id'] for r in heldout}
train=[r for r in records if r['id'] not in heldout_ids]
model_path=pathlib.Path(os.environ.get('LOCALVOICE_QWEN_MODEL',str(root.parent/'asr-models/Qwen3-ASR-0.6B-8bit')))
m=attach(load(str(model_path))._model);opt=optim.Adam(learning_rate=1e-4)
def validate():
 values=[]
 for row in heldout:
  args=prepare(m,str(root/(row['id']+'.wav')),row['corrected'])
  values.append(float(loss(m,*args).item()))
 return sum(values)/len(values)
start=time.monotonic();before=validate();grad=nn.value_and_grad(m,loss)
for epoch in range(2):
 for row in train[:100]:
  args=prepare(m,str(root/(row['id']+'.wav')),row['corrected'])
  value,g=grad(m,*args);opt.update(m,g);mx.eval(m.trainable_parameters(),opt.state,value)
  if time.monotonic()-start>600:raise RuntimeError('Training stopped at the 10-minute limit; base model unchanged.')
after=validate();out=root/'candidate';out.mkdir(exist_ok=True,mode=0o700)
weights={k:v for k,v in tree_flatten(m.trainable_parameters())}
mx.save_safetensors(str(out/'adapter.safetensors'),weights)
report={'training_examples':len(train[:100]),'validation_examples':len(heldout),'validation_loss_before':before,'validation_loss_after':after,'peak_mlx_gb':mx.get_peak_memory()/1e9,'seconds':time.monotonic()-start,'activated':False,'note':'Loss is diagnostic, not a word accuracy guarantee. Listen to candidate evaluation before enabling.'}
(out/'report.json').write_text(json.dumps(report,indent=2))
# Produce blind-comparable outputs for held-out recordings. No candidate is auto-activated.
evaluation=[]
for row in heldout:
 evaluation.append({'id':row['id'],'reference':row['corrected'],'candidate':m.generate(str(root/(row['id']+'.wav')),max_tokens=512).text})
base=load(str(model_path))._model
for item in evaluation:item['base']=base.generate(str(root/(item['id']+'.wav')),max_tokens=512).text
(out/'evaluation.json').write_text(json.dumps(evaluation,ensure_ascii=False,indent=2))
print(json.dumps(report),flush=True)

for file in out.iterdir():file.chmod(0o600)
