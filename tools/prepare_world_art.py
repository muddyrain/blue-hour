"""Reproduce the eight normalized sprites from editable original PNG sources."""
import argparse,hashlib,json
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 output=a.output.resolve();assert output.is_relative_to(ROOT/'.local');output.mkdir(parents=True,exist_ok=False)
 manifest=json.loads((ROOT/'assets/world_v1/manifest.json').read_text(encoding='utf-8'))
 for row in manifest['assets']:
  source=ROOT/'assets/world_v1'/row['source'];assert hashlib.sha256(source.read_bytes()).hexdigest()==row['source_sha256']
  im=Image.open(source).convert('RGBA');assert im.getchannel('A').getextrema()==(0,255)
  im=im.crop(im.getchannel('A').point(lambda x:255 if x>16 else 0).getbbox());im.thumbnail((448,576),Image.Resampling.LANCZOS)
  canvas=Image.new('RGBA',(512,640));canvas.alpha_composite(im,((512-im.width)//2,608-im.height));target=output/row['sprite'];canvas.save(target)
  assert hashlib.sha256(target.read_bytes()).hexdigest()==row['sha256'],row['archetype_id']
 print('WORLD_ART_REPRODUCED',len(manifest['assets']))
if __name__=='__main__':main()
