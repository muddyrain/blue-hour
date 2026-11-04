"""Scoped WORLD-01 flow, exit recovery, legacy compatibility and native 1x movie.
Windows native processes use a separate desktop; this never switches the input desktop.
"""
import argparse,json,os,subprocess,sys,time,socket,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--native',action='store_true');p.add_argument('--case',choices=['flow','suspend','exit','movie','compat','neighborhood','neighborhood-movie','neighborhood-compat'],default='flow');p.add_argument('--pack',type=Path);a=p.parse_args()
 assert subprocess.check_output([a.godot,'--version'],text=True).strip()==(ROOT/'.godot-version').read_text().strip()
 out=a.output.resolve();assert out.is_relative_to(ROOT/'.local');out.mkdir(parents=True,exist_ok=False)
 env=dict(os.environ,APPDATA=str(out/'user'),HOME=str(out/'home'),XDG_DATA_HOME=str(out/'user'))
 phases={'neighborhood':['first','restore','large','small','final'],'neighborhood-movie':['first'],'neighborhood-compat':['old-complete','new-accept','old-suspend','new-refuse'],'flow':['first','restore','second','third','fourth','final'],'suspend':['first','restore'],'exit':['first','resume'],'movie':['first'],'compat':['old-complete','new-accept','old-suspend','new-refuse']}[a.case]
 results=[]
 for phase in phases:
  folder=out/phase;script={'neighborhood':'neighborhood_flow','neighborhood-movie':'neighborhood_movie','neighborhood-compat':'neighborhood_compat','flow':'world_flow','suspend':'world_flow','exit':'world_exit','movie':'world_movie','compat':'rogue_compat'}[a.case]
  flags=['--flow-output='+folder.as_posix(),'--bh-rescue-seed=rogue-sample-008']
  if phase not in ['first','old-complete','old-suspend']:flags+=['--flow-resume']
  if a.case in ['compat','neighborhood-compat']:
   profile=out/('complete-profile' if phase in ['old-complete','new-accept'] else 'suspend-profile')
   env.update(APPDATA=str(profile/'user'),HOME=str(profile/'home'),XDG_DATA_HOME=str(profile/'user'))
   # The explicit old entry writes the exact same canonical isolated path that normal entry reads.
   if phase.startswith('old-') and a.case=='compat':
    flags+=['--flow-fixed','--bh-enemy-trial','--bh-safe-suspend','--bh-camp-prototype']
    flags+=['--bh-progress='+str(profile/('user/Godot/app_userdata/'+re.search(r'config/name="([^"]+)"',(ROOT/'project.godot').read_text(encoding='utf-8'))[1].replace('|','-')+'/playable-v1/run.enemy-v1.json')).replace(chr(92),'/')]
  encoder=None;encoding_log=None
  if a.case in ['movie','neighborhood-movie']:
   assert a.native,'movie requires real native renderer'
   with socket.socket() as probe:probe.bind(('127.0.0.1',0));port=probe.getsockname()[1]
   encoding_log=(out/'encoding.txt').open('wb')
   encoder=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','warning','-f','rawvideo','-pixel_format','rgba','-video_size','1280x720','-framerate','30','-i',f'tcp://127.0.0.1:{port}?listen=1','-an','-c:v','libx264','-preset','veryfast','-crf','21','-pix_fmt','yuv420p','-movflags','+faststart',str(out/'world-1x.mp4')],stdout=encoding_log,stderr=encoding_log)
   flags+=['--flow-stream='+str(port)];time.sleep(.25)
  cmd=[a.godot,'--rendering-method','gl_compatibility','--audio-driver','Dummy']
  if not a.pack or Path(a.godot).resolve().with_suffix('.pck')!=a.pack.resolve():cmd+=['--path',str(ROOT)]
  if a.pack and Path(a.godot).resolve().with_suffix('.pck')!=a.pack.resolve():cmd+=['--main-pack',str(a.pack.resolve())]
  # Export omits tests. Copy only the external driver inheritance chain; game paths stay res:// from PCK.
  if a.pack:
   drivers=out/'drivers';drivers.mkdir(exist_ok=True)
   for name in ['playable_flow','world_flow','world_exit','world_movie','rogue_compat','neighborhood_flow','neighborhood_movie','neighborhood_compat']:
    content=(ROOT/'tests'/(name+'.gd')).read_text(encoding='utf-8').replace('extends "res://tests/','extends "')
    (drivers/(name+'.gd')).write_text(content,encoding='utf-8')
  cmd+=['--script',str(drivers/(script+'.gd')) if a.pack else 'res://tests/'+script+'.gd','--',*flags]
  start=time.monotonic()
  try:
   with (out/(phase+'.txt')).open('wb') as log:
    if a.native:
     assert sys.platform=='win32'
     from windows_test_process import DesktopProcess
     proc=DesktopProcess(cmd,ROOT,env,log,log)
     while proc.poll() is None:
      if time.monotonic()-start>240:proc.kill();raise TimeoutError(phase)
      time.sleep(.1)
     code=proc.wait()
    else:code=subprocess.run([cmd[0],'--headless',*cmd[1:]],cwd=ROOT,env=env,stdout=log,stderr=log,timeout=180).returncode
   if encoder:assert encoder.wait(timeout=30)==0
  finally:
   if encoder and encoder.poll() is None:encoder.kill();encoder.wait()
   if encoding_log:encoding_log.close()
  console=(out/(phase+'.txt')).read_text(encoding='utf-8',errors='replace')
  assert code==0 and not re.search(r'(?m)^(SCRIPT ERROR|ERROR):',console),(phase,code,console[-1800:])
  result=json.loads((folder/'report.json').read_text(encoding='utf-8'));assert result['failures']==0,result
  row={'phase':phase,'pid':result['pid'],'checks':len(result['checks']),'wall_seconds':round(time.monotonic()-start,3),'status':'PASS'};results.append(row);print(row,flush=True)
 (out/'summary.json').write_text(json.dumps({'case':a.case,'native':a.native,'pack':str(a.pack) if a.pack else None,'phases':results,'input':'viewport and existing business intentions','physical_os':'NOT_VERIFIED','display_FPS':'NOT_MEASURED'},indent=2),encoding='utf-8')
if __name__=='__main__':main()
