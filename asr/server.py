"""App-owned local ASR helper. No outbound connections or transcript logging."""
import os,sys
sys.dont_write_bytecode=True
os.environ['HF_HUB_OFFLINE']='1'
os.environ['TRANSFORMERS_OFFLINE']='1'
import argparse,json,contextlib,io,pathlib,miniaudio
from http.server import BaseHTTPRequestHandler,HTTPServer
p=argparse.ArgumentParser();p.add_argument('--model',required=True);p.add_argument('--port',type=int,required=True);p.add_argument('--token',required=True);args=p.parse_args()
from mlx_audio.stt import load
with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):model=load(args.model)
learning=pathlib.Path(os.environ.get('LOCALVOICE_LEARNING_DIRECTORY',str(pathlib.Path(args.model).parent.parent/'Learning')))
if pathlib.Path(args.model).name=='Qwen3-ASR-0.6B-8bit' and (learning/'use-adapter').exists():
 from adapter import attach
 model=attach(model._model)
 weights=learning/'active/adapter.safetensors'
 if not weights.exists():weights=learning/'candidate/adapter.safetensors'
 model.load_weights(str(weights),strict=False)
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*unused):pass
 def reply(self,status,data):
  body=json.dumps(data,ensure_ascii=False).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers()
  try:self.wfile.write(body)
  except (BrokenPipeError,ConnectionResetError):pass
 def do_GET(self):
  self.reply(200 if self.path=='/'+args.token+'/health' else 404,{'ready':True})
 def do_POST(self):
  if self.path!='/'+args.token+'/inference':self.reply(404,{});return
  try:
   size=int(self.headers.get('Content-Length','0'))
   if not 0<size<=65536:raise ValueError('Invalid request size')
   body=json.loads(self.rfile.read(size));audio=pathlib.Path(body['audio'])
   # App records mono PCM WAV; limit duration and files before model allocation.
   info=miniaudio.get_file_info(str(audio))
   if info.file_format!=miniaudio.FileFormat.WAV or info.nchannels!=1 or info.sample_width!=2 or info.sample_rate!=16000 or info.num_frames>16000*125:raise ValueError('Unsupported recording')
   vocab=body.get('vocabulary',[])
   if not isinstance(vocab,list) or len(vocab)>60 or any(not isinstance(x,str) or len(x)>128 for x in vocab):raise ValueError('Invalid vocabulary')
   with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
    result=model.generate(str(audio),max_tokens=2048,temperature=0,hotwords=vocab)
   self.reply(200,{'text':result.text.strip()})
  except Exception:self.reply(500,{'error':'Local speech recognition failed'})
HTTPServer(('127.0.0.1',args.port),Handler).serve_forever()
