"""M8-BUILD-01 Windows real-owner acceptance, isolated profile and optional 1x excerpts."""
import argparse,json,os,re,shutil,socket,subprocess,sys,time
from pathlib import Path
from windows_test_process import DesktopProcess
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--output',required=True,type=Path);p.add_argument('--native',action='store_true');p.add_argument('--movie',action='store_true');a=p.parse_args()
 assert sys.platform=='win32' and not sys.flags.optimize
 assert subprocess.check_output([a.godot,'--version'],text=True).strip()==(ROOT/'.godot-version').read_text().strip()
 out=a.output.resolve();assert out.is_relative_to(ROOT/'.local');out.mkdir(exist_ok=False,parents=True)
 env=dict(os.environ,HOME=str(out/'home'),APPDATA=str(out/'user'),XDG_DATA_HOME=str(out/'user'))
 for name in ['home','user']:(out/name).mkdir()
 results=[]
 for phase in ['first','fight','readback']:
  cmd=[a.godot,'--path',str(ROOT),'--audio-driver','Dummy','--rendering-method','gl_compatibility','--script','res://tests/build_flow.gd']
  if not a.native:cmd+=['--headless']
  cmd+=['--','--flow-output='+(out/phase).as_posix(),'--bh-rescue-seed=m8-build-01-sample-01']
  if phase!='first':cmd+=['--flow-resume']
  encoder=None
  if a.movie:
   assert a.native
   with socket.socket() as probe:probe.bind(('127.0.0.1',0));port=probe.getsockname()[1]
   enc_log=(out/(phase+'-encoder.txt')).open('wb')
   encoder=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','warning','-f','rawvideo','-pixel_format','rgba','-video_size','1280x720','-framerate','30','-i',f'tcp://127.0.0.1:{port}?listen=1','-an','-c:v','libx264','-preset','veryfast','-crf','23','-pix_fmt','yuv420p','-movflags','+faststart',str(out/(phase+'-1x.mp4'))],stdout=enc_log,stderr=enc_log,creationflags=subprocess.CREATE_NO_WINDOW)
   cmd+=['--flow-stream='+str(port)]
  start=time.monotonic()
  with (out/(phase+'.txt')).open('wb') as log:
   proc=DesktopProcess(cmd,ROOT,env,log,log) if a.native else subprocess.Popen(cmd,cwd=ROOT,env=env,stdout=log,stderr=log)
   while proc.poll() is None:
    if time.monotonic()-start>240:proc.kill();raise RuntimeError('phase timeout: '+phase)
    raw=(out/(phase+'.txt')).read_bytes()
    if re.search(rb'(?m)^(SCRIPT ERROR|ERROR):',raw):proc.kill();raise RuntimeError('engine error: '+phase)
    time.sleep(.15)
   code=proc.wait()
  if encoder:
   encoder.wait(timeout=30);enc_log.close();assert encoder.returncode==0
  report=json.loads((out/phase/'report.json').read_text(encoding='utf8'))
  row=dict(phase=phase,pid=report['pid'],exit=code,checks=len(report['checks']),failures=report['failures'],seconds=time.monotonic()-start,frames=report['video_frames']);results.append(row);print(row,flush=True)
  assert code==0 and not report['failures'],row
  if phase=='first':
   for name in ['home','user']:shutil.copytree(out/name,out/'checkpoint-first'/name)
  if phase=='fight':
   for name in ['home','user']:shutil.copytree(out/name,out/'checkpoint-victory'/name)
 (out/'summary.json').write_text(json.dumps(dict(engine=(ROOT/'.godot-version').read_text().strip(),platform='Windows',native=a.native,physical_input='NOT_TESTED',display_fps='NOT_MEASURED',production_gate='BLOCKED',results=results),indent=2),encoding='utf8')
if __name__=='__main__':main()
