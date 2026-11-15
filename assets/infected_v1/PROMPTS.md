# 基础感染者动作图生成来源

2026-11-15。`art_source: host_image`，使用 OpenAI 内置 `image_gen`，真实 AI 生成；工具未返回具体模型版本或费用，不猜测。美术由本项目需求与现有项目 AI 图作为参考生成，不是第三方素材包，也不是 Deadly Days 素材。普通种原五张图逐字节保留。

新运行时资源：`rush/{e,se,s,ne,n}.png`、`heavy/{e,se,s,ne,n}.png`，均在本目录。五个独立源朝向 + W/SW/NW 镜像覆盖八向。所有源图实际返回为 1254×1254 RGBA；整理为 1280×1280、4×4 个 320 方格。原始姿态由图像模型绘制，六帧步态不是旧表切列、重复帧或代码扭曲。

## 动作与整理

按行从左到右，帧 0 待机，1–6 完整左右交替步态，7–9 扑击/推击接触、跟进、恢复，10–11 受击，12–15 倒地。待机为单帧；没有额外承诺呼吸动画。攻击从原有命中事件开始，未添加提前伤害。

整理只做切格、预乘 alpha 等比 Lanczos 缩放与脚点注册，保留图像模型绘制的身体和肢体。每个源朝向使用固定缩放，将待机躯体高度归一为 220 像素；每个源表行使用一个固定的地面注册线纠正生成器整行漂移，不逐帧贴合包围盒。运行时每格根点统一为 (160,304)。所有最终像素文件的 SHA-256 在 `../PROVENANCE.json` 逐项登记；源图 SHA 与注册值见下表。运行时灰绿低饱和由 `infected_palette.gdshader` 统一处理，材质保留世界光照与原 alpha。

## 共同提示

```text
Use case: stylized-concept. Production game sprite animation sheet for an isometric 2D game, hand-painted HD cartoon ink, same modest nonheroic proportions as supplied reference, clean real transparent background. Output ONE SQUARE sheet, exactly 4 columns by 4 rows, sixteen separate full-body drawings in equal cells. No grid lines, text, shadows on ground, props or watermark. Fixed orthographic camera about 25 degrees above ground. ALL 16 poses face EAST (screen RIGHT), side view; no change of facing. Fixed character size, feet root at each cell local (50% width, 88% height), body occupies about 72% cell height; sufficient empty margin for stretched limbs. Dark LOW SATURATION charcoal grey-green civilian clothing, slate trousers, ash skin, matte ink black hair, NO orange/yellow coat, NO blood, NO military clothes, NO bright rim light, NOT pixel art. Read left-to-right then top-to-bottom, indexed 0 to 15: frame 0 idle; frames 1-6 a COMPLETE smooth six-frame LOCOMOTION cycle with visibly alternating near and far legs (1 near foot forward/far back contact, 2 near foot under hip far knee raised, 3 near leg back far leg swinging forward, 4 FAR foot forward/near back opposite contact, 5 far foot under hip NEAR knee raised, 6 far leg back near leg swinging forward). Distinct foot placement and opposed arms in every locomotion drawing; NOT tiny same-pose variations. Frames 7-9 ATTACK, in this order: 7 full extended forward contact lunge with arms reaching RIGHT, 8 forward low follow-through, 9 recovering to hunched stance. Frames 10-11 HIT recoil and settling. Frames 12-15 DEFEAT: knees buckle, falling onto hands, partly on ground, fully lying on ground facing right. No disconnected limbs. Reference is STYLE ONLY, create new continuous locomotion, do not reuse its column arrangement.
```

## 角色身份

### rush

```text
RUSH infected: very lean, narrow shoulders, wiry long limbs, ragged short dark grey-green civilian jacket over dark undershirt. Low forward crouch, neck thrust forward, open clawing hands. Locomotion is a desperate forward pitched RUN with long split strides, bent knees and strong opposite arm swings, alternating left/right support; subtle suspended phase. Attack is a quick feral pounce. Keep a slim silhouette.
```

### heavy

```text
HEAVY infected: hulking round torso, very broad drooped shoulders, massive thick forearms, short thick legs, swollen belly beneath torn dark grey-green civilian work coat (NO uniform). Small head, stooped back. Locomotion is a heavy lumbering WALK, deeply bent support knee, exaggerated left/right weight transfer, feet dragging and lifting alternately, heavy dangling arms. Attack is a massive two-handed forward shove with torso weight. Clearly much wider and bulkier than an ordinary infected, NOT muscular hero.
```

## 朝向与留白约束

初始参考分别为本项目 `assets/m5_anim_01/rush_full.png` 与 `heavy_full.png`，只用于绘画风格和身份。随后每向从该种的侧向生成图参考，使用共同提示与角色身份，并把 EAST 段替换为：

- `e`: EAST: side view, facing screen RIGHT. The back foot remains visible; face profile.
- `se`: SOUTHEAST: front-right three-quarter view, moving DOWN and RIGHT, both chest and right-facing profile visible. Never side view.
- `s`: SOUTH: FRONT view, facing directly toward the camera, moving screen DOWN. Symmetrical viewpoint, nose centered, both shoulders and both knees visible. Absolutely NO side view.
- `ne`: NORTHEAST: rear-right three-quarter view, facing UP and RIGHT, mostly BACK of head and coat visible; no frontal chest, only slight profile. Moving away diagonally.
- `n`: NORTH: strict BACK view, facing directly AWAY from camera, moving screen UP. Back of head, back of jacket and heels visible. NO face or chest in ANY frame, including attack and recoil.

每向附加约束：同一角色、同一配色及服装损坏位置；所有帧完整身体留在各格中央 80%，包括攻击与尸体；全组统一缩小，左右至少 10% 留白；固定脚点在 50% 宽、88% 高；两半步态包含相反脚接触地面的姿态。侧向修订要求全组缩小约 15%，恢复边缘手指。

## 对角朝向修订（实际提示）

### rush/se/revision

```text
Edit the reference sprite sheet. SAME wiry slim rush infected, SAME dark grey-green civilian jacket and trousers, SAME painted style and animation poses. Rotate the character and ALL SIXTEEN poses 45 degrees toward the viewer: FRONT-RIGHT three-quarter camera, clearly show the FULL CHEST and both shoulders, face gazes lower right. The result must look halfway between FRONT and RIGHT SIDE, not another right side profile. Exactly 4 columns by 4 rows of equal cells. In each cell shrink the character to leave AT LEAST 30 pixels of transparent padding on EVERY side, especially under boots. Align all STANDING poses to one fixed ground line at 85% cell height. Six frames indexed 1 to 6 form one full running cycle with opposite-leg contact poses. Preserve the existing arrangement: 0 idle, 1-6 run, 7 contact lunge, 8 follow-through, 9 recovery, 10-11 recoil, 12-15 fall down. All poses must stay within their own cell. No grids, text, props or ground shadows; real alpha background.
```

### rush/ne/revision

```text
Edit the reference sprite sheet. SAME wiry slim rush infected, SAME dark grey-green civilian jacket and trousers, SAME painted style and animation poses. Rotate the character and ALL SIXTEEN poses 45 degrees away from the viewer: REAR-RIGHT three-quarter camera, clearly show the FULL BACK of the jacket and back of head. Hide the face and chest except a tiny right-side cheek edge. Result halfway between BACK and RIGHT SIDE. Exactly 4 columns by 4 rows of equal cells. In each cell shrink the character to leave AT LEAST 30 pixels of transparent padding on EVERY side, especially under boots. Align all STANDING poses to one fixed ground line at 85% cell height. Six frames indexed 1 to 6 form one full running cycle with opposite-leg contact poses. Preserve the existing arrangement: 0 idle, 1-6 run, 7 contact lunge, 8 follow-through, 9 recovery, 10-11 recoil, 12-15 fall down. All poses must stay within their own cell. No grids, text, props or ground shadows; real alpha background.
```

### heavy/se/revision

```text
Edit the reference sheet into a clearly FRONT-RIGHT three-quarter view of this SAME huge broad heavy infected in a dark grey-green torn civilian work coat. ROTATE EVERY POSE 45 degrees TOWARD the camera; show his FULL BELLY, both shoulders, both thick forearms and BOTH sides of his face. His nose and knees point diagonally toward the LOWER RIGHT corner. Do not output side profile. Preserve the bulky proportions, nonheroic painting style and dark low saturation palette. Exactly 4 columns by 4 equal rows. 16 full-body separate drawings: index 0 idle, 1-6 full lumbering walk cycle with OPPOSITE legs alternately reaching forward, 7 two-handed forward contact shove, 8 low follow-through, 9 recovery brace, 10-11 recoil, 12-15 falling then lying down. Every drawing must fit within central 80% of its own cell with clear transparent margins on ALL sides. All standing grounded feet align to 85% cell height. Real transparent alpha, no blood, grid lines, text, weapons, uniforms or shadows.
```

### heavy/se/padding

```text
Keep this exact heavy infected FRONT-RIGHT view, character design, palette, sixteen poses and 4 by 4 sheet layout. Revise ONLY framing: make EVERY character drawing 25 percent SMALLER, uniformly across all 16 cells, leaving a generous clear transparent border around each. In particular restore the COMPLETE extended fingertips in frame 7 (row 2 column 4), which must end well before the right edge. Every hand and foot and corpse fits fully inside its equal square cell with at least 30px blank margin. Same six walking poses and opposite-foot contacts; no additional poses, no labels, no grid lines, real transparent background.
```



## ?????

| ???? | ?????? | ? SHA-256 | ?????? y | ???? |
| --- | --- | --- | --- | --- |
| `assets/infected_v1/rush/e.png` | `exec-bbc2b8d4-734e-4269-887a-7b381d569076.png` | `20db40fa0ffcc57c3b08d0b8cb8e08517ea14d7d89e48820feb8b1a37cc85474` | [297, 283, 277, 256] | 1.04761905 |
| `assets/infected_v1/rush/se.png` | `exec-9639c009-87e2-4d72-bc1f-9489d553b85e.png` | `773a6ad07f016a40b8b9d2a840232a4de41d7673723cd22a17ed78c2d1a1413b` | [308, 301, 295, 277] | 0.91286307 |
| `assets/infected_v1/rush/s.png` | `exec-8193e42e-91dd-40d0-81cf-fc25ed35bce7.png` | `a52523ad2144219fe6c8ecfbbef8de09f69d6f55a6577f014620333b6cd3030f` | [306, 303, 300, 283] | 0.91286307 |
| `assets/infected_v1/rush/ne.png` | `exec-f7884136-6afb-4814-b16f-c6fd6a4a7b33.png` | `30955526ad35351f9f39c8b4550477bfea00e7fcf45856ed9b1e8e8df7a7b53c` | [305, 297, 292, 268] | 0.94017094 |
| `assets/infected_v1/rush/n.png` | `exec-3647ba09-e318-4626-b550-1332d21386ea.png` | `507ebd1330e48680d32c1f826d9f02c05a78278721cfc51a7f07825330594758` | [300, 299, 291, 289] | 1.01851852 |
| `assets/infected_v1/heavy/e.png` | `exec-fe2e1ffa-497e-46f0-8b01-5115811cb54b.png` | `3bb52579899fa0e7dd0b4abfd9890757c74e126822cfa0efa712a5e50a80981c` | [295, 290, 279, 270] | 1.04265403 |
| `assets/infected_v1/heavy/se.png` | `exec-297ad94d-f08d-41e7-a67f-c3f873a14a14.png` | `63dba9432472487299ae86ef33abd5132555e1b119992aee63568ed5ef293652` | [288, 275, 261, 252] | 1.00917431 |
| `assets/infected_v1/heavy/s.png` | `exec-c6e8e2f6-f740-4f1e-8bb1-d9b215b7bd93.png` | `ceafe847e0e52eda8a7d74965c117cb217190237ed5eae3ff8a0b8f8b1e970c7` | [294, 292, 291, 285] | 0.94827586 |
| `assets/infected_v1/heavy/ne.png` | `exec-95700b0a-610d-41c3-a7e6-8ee50aeb8309.png` | `c138b452b29cd215dcdd9c39ea6ca42e6dee4641311bf9a0574adf46a458953d` | [298, 295, 293, 283] | 0.88709677 |
| `assets/infected_v1/heavy/n.png` | `exec-f129d999-bf82-4d5f-a89a-af28b58967c4.png` | `ee13c9847995173811f77a9d418db4ca43bd2faef5db2196c793bcf652b11c35` | [286, 284, 280, 289] | 0.97345133 |
