import {
  Color3,
  Mesh,
  MeshBuilder,
  PointLight,
  Scene,
  ShaderMaterial,
} from './babylon';
import { type Battle, type Explosion, seeded } from '../engine';
import { type Materials, type Quality } from './materials';
import { worldPosition } from './world';

const vertex = `precision highp float;
attribute vec3 position; attribute vec2 uv;
uniform mat4 worldViewProjection; uniform mat4 world;
varying vec2 vUV; varying vec3 vWorld;
void main(){vUV=uv;vWorld=(world*vec4(position,1.)).xyz;gl_Position=worldViewProjection*vec4(position,1.);}`;
const fragment = `precision highp float;
varying vec2 vUV;varying vec3 vWorld;
uniform vec4 puff;uniform float weapon;uniform vec3 fogColor;uniform vec3 eye;uniform float fogDensity;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.)),f.x),f.y);}
float fbm(vec2 p){return .57*noise(p)+.28*noise(p*2.03+7.)+.15*noise(p*4.11+13.);}
void main(){
 vec2 p=vUV*2.-1.;float d=length(p),age=puff.x,seed=puff.y,mode=puff.w;
 float n=fbm(p*3.2+vec2(seed,seed*.71)-vec2(age*.22,age*.7));
 float edge=1.-smoothstep(.55,.98,d+(n-.5)*.33);
 vec3 color;float alpha;
 if(mode<.5){
  float heat=clamp((1.-d)*1.2+n*.55-age*.55,0.,1.);
  color=mix(vec3(.72,.055,.006),vec3(2.6,.62,.045),smoothstep(.12,.62,heat));
  color=mix(color,vec3(4.,2.8,.95),smoothstep(.64,.97,heat));
  alpha=edge*mix(.6,1.,n)*puff.z;
 }else if(mode<1.5){
  float light=.42+.34*vUV.y+.25*n;
  color=mix(vec3(.085,.082,.076),vec3(.44,.43,.39),light);
  color+=vec3(.23,.075,.009)*max(0.,1.-age*1.7)*(1.-vUV.y);
  alpha=edge*(.5+.5*n)*puff.z;
 }else if(mode<2.5){
  float ringDistance=(d-.72)*13.;float ring=exp(-ringDistance*ringDistance);
  color=vec3(.58,.5,.37)*(0.7+n*.5);alpha=ring*(.25+n*.75)*puff.z;
 }else if(mode<3.5){
  color=vec3(4.,2.9,1.5);alpha=exp(-d*d*7.)*puff.z*(1.-smoothstep(.6,1.,d));
 }else{
  color=vec3(.075,.064,.049);alpha=edge*(.45+n*.55)*puff.z;
 }
 if(mode<.5 || (mode>1.5 && mode<3.5)) {
   if(weapon>4.5 && weapon<5.5) color=vec3(color.b*.6,color.r*.8,color.r);
   else if(weapon>2.5 && weapon<3.5) color=vec3(color.r*.68,color.b*.7,color.r);
 }
 float fog=1.-exp(-pow(length(vWorld-eye)*fogDensity,2.));
 color=mix(color,fogColor,fog);
 if(alpha<.008)discard;gl_FragColor=vec4(color,alpha);
}`;

type SpriteState = {
  age: number;
  seed: number;
  alpha: number;
  mode: number;
  weapon?: number;
};

/** Bounded visual pools; time and randomness are independent of render frequency. */
export class ExplosionEffects {
  private sprites: Mesh[] = [];
  private fragments: Mesh[] = [];
  private scorch: Mesh[] = [];
  private material: ShaderMaterial;
  readonly light: PointLight;
  constructor(
    private scene: Scene,
    private materials: Materials,
    private quality: Quality,
    private mobile: boolean,
  ) {
    this.material = new ShaderMaterial(
      'turbulent-explosion-volume',
      scene,
      { vertexSource: vertex, fragmentSource: fragment },
      {
        attributes: ['position', 'uv'],
        uniforms: [
          'worldViewProjection',
          'world',
          'puff',
          'weapon',
          'fogColor',
          'eye',
          'fogDensity',
        ],
        needAlphaBlending: true,
      },
    );
    this.material.backFaceCulling = false;
    this.material.disableDepthWrite = true;
    this.material.onBindObservable.add((mesh) => {
      const state = mesh?.metadata as SpriteState | undefined;
      const effect = this.material.getEffect();
      if (!state || !effect) return;
      effect.setFloat4('puff', state.age, state.seed, state.alpha, state.mode);
      effect.setFloat('weapon', state.weapon ?? 0);
      effect.setColor3('fogColor', scene.fogColor);
      effect.setFloat('fogDensity', scene.fogDensity);
      if (scene.activeCamera)
        effect.setVector3('eye', scene.activeCamera.globalPosition);
    });
    this.light = new PointLight(
      'shared-explosion-flash',
      worldPosition(0, 0),
      scene,
    );
    this.light.diffuse = new Color3(1, 0.42, 0.095);
    this.light.intensity = 0;
    this.light.range = 32;
  }
  private sprite(pool: Mesh[], index: number) {
    let mesh = pool[index];
    if (!mesh) {
      mesh = MeshBuilder.CreatePlane(
        'pooled-blast-volume',
        { size: 1 },
        this.scene,
      );
      mesh.material = this.material;
      mesh.isPickable = false;
      mesh.metadata = {
        age: 0,
        seed: 0,
        alpha: 0,
        mode: 0,
      } satisfies SpriteState;
      pool.push(mesh);
    }
    mesh.setEnabled(true);
    return mesh;
  }
  private puff(
    index: number,
    e: Explosion,
    age: number,
    mode: number,
    x: number,
    y: number,
    elevation: number,
    size: number,
    alpha: number,
    seed: number,
  ) {
    const mesh = this.sprite(this.sprites, index);
    mesh.position.copyFrom(worldPosition(e.x + x, e.y + y, elevation));
    mesh.scaling.set(size, mode === 1 ? size * 1.08 : size, 1);
    mesh.rotation.set(mode === 2 ? Math.PI / 2 : 0, 0, 0);
    mesh.billboardMode =
      mode === 2 ? Mesh.BILLBOARDMODE_NONE : Mesh.BILLBOARDMODE_ALL;
    Object.assign(mesh.metadata, {
      age,
      seed,
      alpha,
      mode,
      weapon: e.weapon ?? 0,
    });
  }
  update(b: Battle, effectScale: number, time = b.elapsed) {
    const lightMode = this.mobile || this.quality === 'performance';
    const slots = Math.max(
      1,
      Math.floor(
        (lightMode ? 3 : this.quality === 'cinematic' ? 10 : 7) * effectScale,
      ),
    );
    // Prioritize nearby recent explosions; distant shells do not evict a visible blast.
    const visible = b.explosions
      .filter(
        (e) =>
          time - e.bornAt < (e.kind === 'impact' ? 0.6 : 5.5) &&
          Math.hypot(e.x - b.player.x, e.y - b.player.y) <
            (lightMode ? 800 : 1250),
      )
      .slice(-slots);
    let spriteCount = 0,
      fragmentCount = 0,
      brightest = 0;
    this.light.intensity = 0;
    for (const e of visible) {
      const age = Math.max(0, time - e.bornAt),
        s = e.scale;
      if (e.kind === 'impact') {
        if (age < 0.28)
          this.puff(
            spriteCount++,
            e,
            age,
            3,
            0,
            0,
            1.9,
            (2 + age * 17) * s,
            1 - age / 0.28,
            e.id,
          );
        if (age < 0.48 && (e.weapon === 3 || e.weapon === 5))
          this.puff(
            spriteCount++,
            e,
            age,
            2,
            0,
            0,
            0.1,
            (2 + age * 28) * s,
            1 - age / 0.48,
            e.id,
          );
        if (age < 0.6 && e.weapon !== 5)
          this.puff(
            spriteCount++,
            e,
            age,
            1,
            0,
            0,
            1.7 + age,
            (1 + age * 4) * s,
            (1 - age / 0.6) * 0.4,
            e.id,
          );
        continue;
      }
      const masonry = e.kind === 'masonry',
        small = e.kind === 'shell';
      const rand = seeded(e.id * 193 + Math.floor(e.x * 7 + e.y * 11));
      if (!masonry && age < 0.2) {
        this.puff(
          spriteCount++,
          e,
          age,
          3,
          0,
          0,
          1.7 * s,
          (3 + age * 58) * s,
          (1 - age / 0.2) * 0.95,
          e.id,
        );
      }
      const fireCount = masonry ? 0 : lightMode ? 2 : small ? 3 : 5;
      for (let i = 0; i < fireCount; i++) {
        const angle = rand() * Math.PI * 2,
          offset = rand() * 18 * s;
        const duration = 0.65 + rand() * 0.3;
        if (age >= duration) continue;
        const growth = 1 - Math.exp(-age * 13);
        this.puff(
          spriteCount++,
          e,
          age,
          0,
          Math.cos(angle) * offset * growth,
          Math.sin(angle) * offset * growth,
          (0.8 + i * 0.24 + age * 2.8) * s,
          (1.7 + growth * (3.2 + i * 0.3)) * s,
          Math.min(1, (duration - age) * 3),
          e.id * 2.7 + i * 12.1,
        );
      }
      const smokeCount = lightMode ? 2 : small ? 3 : 6;
      for (let i = 0; i < smokeCount; i++) {
        const angle = rand() * Math.PI * 2,
          drift = 8 + rand() * 11;
        const t = age - i * 0.065;
        if (t < 0.08) continue;
        const fade =
          Math.min(1, (t - 0.08) * 3) *
          Math.max(0, 1 - t / (small ? 2.8 : 5.2));
        if (fade <= 0) continue;
        this.puff(
          spriteCount++,
          e,
          t,
          1,
          (Math.cos(angle) * drift * Math.sqrt(t) + t * 8) * s,
          Math.sin(angle) * drift * Math.sqrt(t) * s,
          (0.8 + t * (masonry ? 0.7 : 2.5) + i * 0.32) * s,
          (2.1 + Math.sqrt(t) * 3.3) * s,
          fade * (masonry ? 0.46 : 0.8),
          e.id * 5.3 + i * 14.7,
        );
      }
      if (age < 1.25) {
        this.puff(
          spriteCount++,
          e,
          age,
          2,
          0,
          0,
          0.085,
          (2 + Math.pow(age, 0.65) * 22) * s,
          (1 - age / 1.25) * 0.62,
          e.id * 4.1,
        );
      }
      const debrisCount = lightMode ? 3 : this.quality === 'cinematic' ? 12 : 8;
      for (let i = 0; i < debrisCount; i++) {
        const angle = rand() * Math.PI * 2,
          speed = (2.5 + rand() * 6) * s;
        const lift = (3.5 + rand() * 5) * Math.sqrt(s),
          spin = rand() * 8 - 4;
        const size = (0.09 + rand() * 0.18) * s;
        if (age > 2.4) continue;
        let mesh = this.fragments[fragmentCount];
        if (!mesh) {
          mesh = MeshBuilder.CreateBox(
            'pooled-ballistic-fragment',
            { size: 1 },
            this.scene,
          );
          mesh.isPickable = false;
          this.fragments.push(mesh);
        }
        fragmentCount++;
        const flight = Math.min(
          age,
          (lift + Math.sqrt(lift * lift + 19.6)) / 9.8,
        );
        const travel = (speed * (1 - Math.exp(-flight * 0.65))) / 0.65;
        mesh.position.copyFrom(
          worldPosition(
            e.x,
            e.y,
            Math.max(0.12, 1 + lift * age - 4.9 * age * age),
          ),
        );
        mesh.position.x += Math.cos(angle) * travel;
        mesh.position.z += Math.sin(angle) * travel;
        mesh.rotation.set(
          spin * flight,
          angle + flight * 4,
          flight * spin * 0.7,
        );
        mesh.scaling.set(size * 2.2, size * 0.7, size);
        mesh.material = masonry
          ? this.materials.concrete
          : age < 0.35
            ? this.materials.ember
            : this.materials.steel;
        mesh.visibility = Math.min(1, (2.4 - age) * 2);
        mesh.setEnabled(true);
      }
      const energy = Math.max(0, 1 - age / 0.36) ** 2 * s;
      if (!lightMode && !masonry && energy > brightest) {
        brightest = energy;
        this.light.position.copyFrom(worldPosition(e.x, e.y, 3 * s));
        this.light.intensity = energy * 95;
        this.light.range = 25 + s * 13;
      }
    }
    for (let i = spriteCount; i < this.sprites.length; i++)
      this.sprites[i].setEnabled(false);
    for (let i = fragmentCount; i < this.fragments.length; i++)
      this.fragments[i].setEnabled(false);
    const scars = b.scars.slice(-(lightMode ? 12 : 42));
    scars.forEach((scar, i) => {
      const mesh = this.sprite(this.scorch, i);
      mesh.billboardMode = Mesh.BILLBOARDMODE_NONE;
      mesh.rotation.set(Math.PI / 2, 0, 0);
      mesh.position.copyFrom(worldPosition(scar.x, scar.y, 0.079));
      mesh.scaling.set(scar.r * 0.28, scar.r * 0.28, 1);
      Object.assign(mesh.metadata, {
        age: 0,
        seed: scar.x + scar.y,
        alpha: 0.84,
        mode: 4,
        weapon: 0,
      });
    });
    for (let i = scars.length; i < this.scorch.length; i++)
      this.scorch[i].setEnabled(false);
  }
}
