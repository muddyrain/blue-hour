"""Pinned public checks; no private archives or real user profiles required."""
import argparse, datetime, json, os, re, shutil, subprocess, sys, uuid
from pathlib import Path
if sys.flags.optimize:raise RuntimeError('Optimized Python is prohibited for check gates')
ROOT=Path(__file__).resolve().parents[1]
LOCK=(ROOT/'.godot-version').read_text(encoding='utf-8').strip()

def main():
 p=argparse.ArgumentParser();p.add_argument('action',choices=['check','run','export']);p.add_argument('--godot');entry=p.add_mutually_exclusive_group();entry.add_argument('--enemy-trial',action='store_true');p.add_argument('--profile',type=Path);p.add_argument('--output',type=Path);p.add_argument('--preset',default='Windows Desktop');p.add_argument('--templates',type=Path,help='Directory containing pinned official export templates');a=p.parse_args()
 exe=a.godot or os.environ.get('GODOT_BIN') or shutil.which('godot') or shutil.which('godot4')
 if not exe:raise RuntimeError('Specify --godot or GODOT_BIN with the pinned engine')
 version=subprocess.check_output([exe,'--version'],text=True,timeout=15).strip();assert version==LOCK,(version,LOCK)
 from build_navigation import report_available, isolated_env
 report_available()
 if a.action=='export':
  output=(a.output or ROOT/'.local/exports/windows/blue-hour.exe').resolve();assert output.is_relative_to(ROOT/'.local'),'Use a project-local isolated output';output.parent.mkdir(parents=True,exist_ok=True)
  env=isolated_env(output.parent/'profile')
  if a.templates:
   templates=a.templates.resolve();version='.'.join(LOCK.split('.')[:3])+'.stable'
   assert (templates/'version.txt').read_text().strip()==version,'Template version mismatch'
   destination=Path(env['XDG_DATA_HOME'])/'godot/export_templates'/version
   if os.name=='nt':destination=Path(env['APPDATA'])/'Godot/export_templates'/version
   shutil.copytree(templates,destination,dirs_exist_ok=True)
  z=subprocess.run([exe,'--headless','--path',str(ROOT),'--audio-driver','Dummy','--export-release',a.preset,str(output)],cwd=ROOT,env=env,capture_output=True,text=True,encoding='utf-8')
  log=z.stdout+z.stderr;(output.parent/'export.log').write_text(log,encoding='utf-8')
  for line in log.splitlines():
   if 'BH_NAVIGATION' in line or re.match(r'^(SCRIPT ERROR|ERROR):',line):print(line,flush=True)
  if z.returncode or re.search(r'(?m)^(SCRIPT ERROR|ERROR):',log) or not output.is_file():return 1
  print('BH_EXPORT_READY',output,flush=True);return 0
 if a.action=='run':
  env=dict(os.environ);flags=[]
  profile=a.profile or (ROOT/'.local/developer-enemy' if a.enemy_trial else None)
  if profile is not None:
   profile=profile.resolve();assert profile.is_relative_to(ROOT/'.local'),'Use a project-local isolated profile';profile.mkdir(parents=True,exist_ok=True)
   env=isolated_env(profile)
   flags+=['--bh-progress='+str(profile/'run.enemy-v1.json'),'--bh-audio-settings='+str(profile/'audio.json')]
  return subprocess.call([exe,'--path',str(ROOT),'--rendering-method','gl_compatibility','--',*flags],cwd=ROOT,env=env)
 job=(a.output or ROOT/'.local/public-checks'/(datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8])).resolve();assert job.is_relative_to(ROOT/'.local'),'Use a project-local isolated output';job.mkdir(parents=True,exist_ok=False)
 env=isolated_env(job)
 rows=[]
 def execute(label,args,flags=None,expected=0):
  folder=job/label;folder.mkdir();cmd=[exe,'--headless','--path',str(ROOT),'--audio-driver','Dummy',*args]
  flags=list(flags if flags is not None else [])
  cmd+=['--',*flags,'--bh-progress='+(folder/'run.enemy-v1.json').as_posix(),'--bh-audio-settings='+(folder/'audio.json').as_posix()]
  if label=='known-hash-cycle':cmd+=['--cycle-output='+(folder/'cycle.json').as_posix()]
  if label=='record-hash':cmd+=['--record-output='+(folder/'data').as_posix()]
  if label=='neighborhood-data':cmd+=['--neighborhood-output='+(folder/'data.json').as_posix()]
  with (folder/'console.txt').open('xb') as out:z=subprocess.run(cmd,cwd=ROOT,stdout=out,stderr=out,env=env,timeout=600 if label=='progression_save' else 300 if label=='m48-sources' else 150)
  text=(folder/'console.txt').read_text(encoding='utf-8',errors='replace');assert z.returncode==expected and not re.search(r'(?m)^(SCRIPT ERROR|ERROR):',text),(label,z.returncode,text[-2000:])
  assert all(int(n)==0 for n in re.findall(r'"failures"\s*:\s*(\d+)',text)),(label,'structured failures')
  if label=='known-hash-cycle':assert 'MINIMAL_HASH_CYCLE=true' in text and 'EXACT_RECORD_ROUNDTRIP=true' in text
  if label.startswith('startup-'):assert 'BH_READY' in text
  if label=='action-generation-cache':assert 'BH_ACTION_GENERATION_CACHE ' in text
  rows.append({'case':label,'exit':z.returncode,'expected_exit':expected,'status':'EXPECTED_KNOWN_FAILURE' if expected else 'PASS'});print(label,rows[-1]['status'],flush=True)
 execute('import',['--editor','--import'])
 execute('startup-default',['--quit-after','3'])
 execute('startup-111',['--quit-after','3'])
 execute('smoke-loop',['--script','res://tests/smoke_loop.gd'],[])
 execute('smoke-wait',['--script','res://tests/smoke_wait.gd'],[])
 execute('mission-loading',['--script','res://tests/mission_loading.gd'],[])
 execute('navigation-cache',['--script','res://tests/navigation_cache.gd'],[])
 execute('navigation-routes',['--script','res://tests/navigation_routes.gd'],[])
 execute('navigation-fallback',['--script','res://tests/navigation_fallback.gd'],[])
 z=subprocess.run([sys.executable,'tools/test_navigation_build.py'],cwd=ROOT,capture_output=True);(job/'navigation-build.txt').write_bytes(z.stdout+z.stderr);assert z.returncode==0,z.stderr
 rows.append({'case':'navigation-build','exit':z.returncode,'expected_exit':0,'status':'PASS'})
 execute('action-generation-cache',['--script','res://tests/action_generation_cache.gd'],[])
 execute('run-feel',['--script','res://tests/run_feel.gd'],[])
 execute('ground-seams',['--script','res://tests/ground_seams.gd'],[])
 execute('surface-lines',['--script','res://tests/surface_lines.gd'],[])
 execute('audio-feedback',['--script','res://tests/audio_feedback.gd'],[])
 for name in ['playable_entry','presentation','squad_recruit','squad_long_run','camp_scene_contracts','weapon_inventory','combat_los','navigation_nearest','night_pressure','campaign_pressure','harbor_warehouse','progression_contracts','progression_save','maps_events','sortie_events','contact_damage','contact_separation','animation/motion','animation/normal_stability','animation/infected_v1','animation/special_infected_v1','animation/survivors_v1','animation/weapon_holding']:
  execute(name.replace('/','-'),['--script','res://tests/'+name+'.gd'])
 for name in ['rogue_navigation','hud_compact','world_data']:
  execute(name.replace('_','-'),['--script','res://tests/'+name+'.gd'])
 execute('journal-cache',['--script','res://tests/journal_cache.gd'],[])
 execute('neighborhood-data',['--script','res://tests/neighborhood_data.gd'])
 execute('task-data',['--script','res://tests/task_data.gd'],[])
 execute('weapon-magazine',['--script','res://tests/weapon_magazine.gd'],[])
 for name in ['campaign_rules','boss_behavior','campaign_contracts','encounter_termination','build_items','basic_support','build_contracts','combat_patterns_v1','toxic_v1','combat_integration','search_assignments','search_work_view','special_powers','power_boundaries','persona_rules','persona_runtime','persona_ui','exploration_contracts','exploration_presentation','exploration_boundaries','worldgen_contracts','worldgen_hud','worldgen_boundaries','worldgen_picking']:
  execute(name.replace('_','-'),['--script','res://tests/'+name+'.gd'],[])
 execute('known-hash-cycle',['--script','res://tests/known_hash_cycle.gd'])
 execute('record-hash',['--script','res://tests/record_hash.gd'])
 for name in ['r2_art','r2_save_cache','r2_save_failure','level_policy','level_summary','level_generation']:
  execute(name.replace('_','-'),['--script','res://tests/'+name+'.gd'],[])
 for name in ['m48_economy','m48_source_codec','m48_build_powers','m48_runtime_effects','m48_patterns','m48_components','m48_sources','m48_drop_grades','m48_record_transport','m48_record_cache','journal_prefix']:
  execute(name.replace('_','-'),['--script','res://tests/'+name+'.gd'],[])
 z=subprocess.run([sys.executable,'tools/validate_assets.py'],cwd=ROOT,capture_output=True);(job/'assets.txt').write_bytes(z.stdout+z.stderr);assert z.returncode==0,z.stderr
 result={'status':'PASS_PUBLIC_SUBSET_WITH_EXACT_RECORD_TRANSPORT','legacy_engine_json_cycle':'REPRODUCED','production_gate':'BLOCKED','cases':rows,'private_archive_matrix':'NOT_INCLUDED','physical_os':'NOT_VERIFIED'}
 (job/'summary.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result));return 0

if __name__=='__main__':
 try:sys.exit(main())
 except Exception as error:print('PUBLIC_CHECK_FAILED',error,file=sys.stderr);sys.exit(1)
