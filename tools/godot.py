"""Pinned public checks; no private archives or real user profiles required."""
import argparse, datetime, json, os, re, shutil, subprocess, sys, uuid
from pathlib import Path
if sys.flags.optimize:raise RuntimeError('Optimized Python is prohibited for check gates')
ROOT=Path(__file__).resolve().parents[1]
LOCK=(ROOT/'.godot-version').read_text(encoding='utf-8').strip()

def main():
 p=argparse.ArgumentParser();p.add_argument('action',choices=['check','run']);p.add_argument('--godot');entry=p.add_mutually_exclusive_group();entry.add_argument('--enemy-trial',action='store_true');entry.add_argument('--legacy-entry',action='store_true');p.add_argument('--profile',type=Path);p.add_argument('--output',type=Path);a=p.parse_args()
 exe=a.godot or os.environ.get('GODOT_BIN') or shutil.which('godot') or shutil.which('godot4')
 if not exe:raise RuntimeError('Specify --godot or GODOT_BIN with the pinned engine')
 version=subprocess.check_output([exe,'--version'],text=True,timeout=15).strip();assert version==LOCK,(version,LOCK)
 if a.action=='run':
  env=dict(os.environ);flags=['--bh-enemy-trial','--bh-safe-suspend','--bh-camp-prototype'] if a.enemy_trial else ['--bh-legacy-entry'] if a.legacy_entry else []
  profile=a.profile or (ROOT/'.local/developer-enemy' if a.enemy_trial else None)
  if profile is not None:
   profile=profile.resolve();assert profile.is_relative_to(ROOT/'.local'),'Use a project-local isolated profile';profile.mkdir(parents=True,exist_ok=True)
   env.update(HOME=str(profile/'home'),APPDATA=str(profile/'user'),XDG_DATA_HOME=str(profile/'user'))
   flags+=['--bh-progress='+str(profile/('run.json' if a.legacy_entry else 'run.enemy-v1.json')),'--bh-audio-settings='+str(profile/'audio.json')]
  return subprocess.call([exe,'--path',str(ROOT),'--rendering-method','gl_compatibility','--',*flags],cwd=ROOT,env=env)
 job=(a.output or ROOT/'.local/public-checks'/(datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8])).resolve();assert job.is_relative_to(ROOT/'.local'),'Use a project-local isolated output';job.mkdir(parents=True,exist_ok=False)
 env=dict(os.environ,HOME=str(job/'home'),APPDATA=str(job/'user'),XDG_DATA_HOME=str(job/'user'))
 rows=[]
 def execute(label,args,flags=None,expected=0):
  folder=job/label;folder.mkdir();cmd=[exe,'--headless','--path',str(ROOT),'--audio-driver','Dummy',*args]
  flags=list(flags if flags is not None else ([] if label=='startup-default' else ['--bh-legacy-entry']))
  cmd+=['--',*flags,'--bh-progress='+str(folder/('run.enemy-v1.json' if label in ['startup-default','rogue-contracts','world-contracts','neighborhood-contracts','task-contracts','task-data','campaign-contracts','journal-cache','world-bus'] or '--bh-enemy-trial' in flags else 'run.json')),'--bh-audio-settings='+str(folder/'audio.json')]
  if label=='known-hash-cycle':cmd+=['--cycle-output='+(folder/'cycle.json').as_posix()]
  if label=='record-hash':cmd+=['--record-output='+(folder/'data').as_posix()]
  if label=='closeout-view':cmd+=['--view-output='+(folder/'frames').as_posix()]
  if label=='neighborhood-view':cmd+=['--view-output='+(folder/'frames').as_posix()]
  if label=='neighborhood-data':cmd+=['--neighborhood-output='+(folder/'data.json').as_posix()]
  if label=='rogue-data':cmd+=['--rogue-data-output='+(folder/'data.json').as_posix()]
  with (folder/'console.txt').open('xb') as out:z=subprocess.run(cmd,cwd=ROOT,stdout=out,stderr=out,env=env,timeout=150)
  text=(folder/'console.txt').read_text(encoding='utf-8',errors='replace');assert z.returncode==expected and not re.search(r'(?m)^(SCRIPT ERROR|ERROR):',text),(label,z.returncode,text[-2000:])
  if label=='known-hash-cycle':assert 'MINIMAL_HASH_CYCLE=true' in text and 'EXACT_RECORD_ROUNDTRIP=true' in text
  if label.startswith('startup-'):assert 'BH_READY' in text
  rows.append({'case':label,'exit':z.returncode,'expected_exit':expected,'status':'EXPECTED_KNOWN_FAILURE' if expected else 'PASS'});print(label,rows[-1]['status'],flush=True)
 execute('import',['--editor','--import'])
 execute('startup-default',['--quit-after','3'])
 execute('startup-legacy',['--quit-after','3'],['--bh-legacy-entry'])
 execute('startup-111',['--quit-after','3'],['--bh-enemy-trial','--bh-safe-suspend','--bh-camp-prototype'])
 for name in ['playable_entry','smoke','presentation','weapon_inventory','combat_los','navigation_nearest','night_pressure','contact_damage','contact_separation','animation/motion','animation/normal_stability','animation/infected_v1']:
  execute(name.replace('/','-'),['--script','res://tests/'+name+'.gd'])
 for name in ['rogue_data','rogue_navigation','hud_compact','rogue_legacy_scope','world_data']:
  execute(name.replace('_','-'),['--script','res://tests/'+name+'.gd'])
 execute('world-bus',['--script','res://tests/world_bus.gd'],[])
 execute('journal-cache',['--script','res://tests/journal_cache.gd'],[])
 execute('closeout-view',['--script','res://tests/closeout_view.gd'])
 execute('neighborhood-data',['--script','res://tests/neighborhood_data.gd'])
 execute('neighborhood-view',['--script','res://tests/neighborhood_view.gd'])
 execute('neighborhood-contracts',['--script','res://tests/neighborhood_contracts.gd'],[])
 execute('world-contracts',['--script','res://tests/world_contracts.gd'],[])
 execute('rogue-contracts',['--script','res://tests/rogue_contracts.gd'],[])
 execute('task-data',['--script','res://tests/task_data.gd'],[])
 execute('task-contracts',['--script','res://tests/task_contracts.gd'],[])
 execute('weapon-magazine',['--script','res://tests/weapon_magazine.gd'],[])
 for name in ['campaign_rules','boss_behavior','campaign_contracts','encounter_termination','build_items','basic_support','build_contracts','combat_patterns_v1','toxic_v1','combat_integration','search_assignments','search_work_view','special_powers','power_boundaries']:
  execute(name.replace('_','-'),['--script','res://tests/'+name+'.gd'],[])
 execute('known-hash-cycle',['--script','res://tests/known_hash_cycle.gd'])
 execute('record-hash',['--script','res://tests/record_hash.gd'])
 z=subprocess.run([sys.executable,'tools/validate_assets.py'],cwd=ROOT,capture_output=True);(job/'assets.txt').write_bytes(z.stdout+z.stderr);assert z.returncode==0,z.stderr
 result={'status':'PASS_PUBLIC_SUBSET_WITH_EXACT_RECORD_TRANSPORT','legacy_engine_json_cycle':'REPRODUCED','production_gate':'BLOCKED','cases':rows,'private_archive_matrix':'NOT_INCLUDED','physical_os':'NOT_VERIFIED'}
 (job/'summary.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result));return 0

if __name__=='__main__':
 try:sys.exit(main())
 except Exception as error:print('PUBLIC_CHECK_FAILED',error,file=sys.stderr);sys.exit(1)
