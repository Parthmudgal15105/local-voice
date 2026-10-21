"""Disposable capacity probe: no deployed weights or adapters are modified."""
import os
os.environ['HF_HUB_OFFLINE']='1';os.environ['TRANSFORMERS_OFFLINE']='1'
import time,json,sys,resource
import mlx.core as mx,mlx.nn as nn,mlx.optimizers as optim
from mlx.utils import tree_flatten
from mlx_audio.stt import load
mx.set_memory_limit(6*1024**3);mx.set_cache_limit(256*1024**2)
def attach(m):
 m.freeze()
 for layer in m.model.layers[-4:]:
  for name in ['q_proj','v_proj']:
   base=getattr(layer.self_attn,name);setattr(layer.self_attn,name,LoRA(base))
 return m

class LoRA(nn.Module):
 def __init__(self,base):
  super().__init__();self.base=base
  self.a=mx.random.normal((base.weight.shape[1]*32//base.bits if isinstance(base,nn.QuantizedLinear) else base.weight.shape[1],8))*0.01
  self.b=mx.zeros((8,base.weight.shape[0]))
 def __call__(self,x):return self.base(x)+(x@self.a@self.b)
def prepare(m,audio_path,text):
 features,mask,n=m._preprocess_audio(audio_path)
 audio=mx.stop_gradient(m.get_audio_features(features,mask));mx.eval(audio)
 prompt=m._build_prompt(n,None,None)
 target=m._tokenizer.encode(text,add_special_tokens=False)
 if not target or len(target)>512:raise ValueError("Training text must be 1–512 tokens")
 ids=mx.concatenate([prompt,mx.array([target[:-1]])],axis=1)
 embeds=mx.stop_gradient(m._build_inputs_embeds(ids,audio));mx.eval(embeds)
 return embeds,mx.array([target]),prompt.shape[1]-1

def loss(model,embeds,labels,start):
 hidden=model.model(inputs_embeds=embeds)[:,start:,:]
 logits=model.lm_head(hidden) if model.lm_head is not None else model.model.embed_tokens.as_linear(hidden)
 return nn.losses.cross_entropy(logits,labels,reduction='mean')
