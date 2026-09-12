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

export const blastVertex = `precision highp float;
attribute vec3 position; attribute vec2 uv;
uniform mat4 worldViewProjection; uniform mat4 world;
varying vec2 vUV; varying vec3 vWorld;
void main(){vUV=uv;vWorld=(world*vec4(position,1.)).xyz;gl_Position=worldViewProjection*vec4(position,1.);}`;
export const blastFragment = `precision highp float;
varying vec2 vUV;varying vec3 vWorld;
uniform vec4 puff;uniform float weapon;uniform vec3 fogColor;uniform vec3 eye;uniform float fogDensity;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.)),f.x),f.y);}
float fbm(vec2 p){return .57*noise(p)+.28*noise(p*2.03+7.)+.15*noise(p*4.11+13.);}
void main(){
 vec2 p=vUV*2.-1.;float d=length(p),age=puff.x,seed=puff.y,mode=puff.w;
 float n=fbm(p*3.2+vec2(seed,seed*.71)-vec2(age*.22,age*.7));
 float edge=1.-smoothstep(.48,.98,d+(n-.5)*.4);
 vec3 color;float alpha;
 if(mode<.5){
  float heat=clamp((1.-d)*1.2+n*.55-age*.55,0.,1.);
  color=mix(vec3(.72,.055,.006),vec3(2.6,.62,.045),smoothstep(.12,.62,heat));
  color=mix(color,vec3(4.,2.8,.95),smoothstep(.64,.97,heat));
  color=mix(color,vec3(.13,.095,.066),smoothstep(.12,.58,age)*.86);
  alpha=edge*mix(.6,1.,n)*puff.z;
 }else if(mode<1.5){
  vec3 normal=normalize(vec3(p.x,p.y,sqrt(max(.02,1.-dot(p,p)))));
  float light=.22+.5*max(0.,dot(normal,normalize(vec3(-.45,.75,.55))))+.12*n;
  color=mix(vec3(.065,.061,.052),vec3(.43,.40,.34),light);
  color+=vec3(.23,.075,.009)*max(0.,1.-age*1.7)*(1.-vUV.y);
  alpha=edge*(.5+.5*n)*puff.z;
 }else if(mode<2.5){
  float ringDistance=(d-.68+(n-.5)*.23)*10.;float ring=exp(-ringDistance*ringDistance);
  color=vec3(.58,.5,.37)*(0.7+n*.5);alpha=ring*(.25+n*.75)*puff.z;
 }else if(mode<3.5){
  color=vec3(4.,2.9,1.5);alpha=exp(-d*d*7.)*puff.z*(1.-smoothstep(.6,1.,d));
 }else if(mode<4.5){
  color=vec3(.075,.064,.049);alpha=edge*(.45+n*.55)*puff.z;
 }else if(mode<5.5){
  color=mix(vec3(.25,.215,.17),vec3(.53,.47,.36),n*.65+vUV.y*.25);
  alpha=edge*(.35+n*.65)*puff.z;
 }else{
  float core=exp(-p.y*p.y*18.);
  float taper=1.-smoothstep(.35,1.,abs(p.x));
  color=mix(vec3(3.,.42,.015),vec3(5.,3.8,1.7),core*(.55+.45*vUV.x));
  alpha=core*taper*puff.z;
 }
 if(mode<.5 || (mode>1.5 && mode<3.5) || mode>5.5) {
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
      { vertexSource: blastVertex, fragmentSource: blastFragment },
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
    mesh.scaling.set(
      size,
      mode === 1 ? size * 1.08 : mode === 5 ? size * 0.38 : size,
      1,
    );
    mesh.rotation.set(mode === 2 || mode === 6 ? Math.PI / 2 : 0, 0, 0);
    mesh.billboardMode =
      mode === 2 || mode === 6
        ? Mesh.BILLBOARDMODE_NONE
        : Mesh.BILLBOARDMODE_ALL;
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
        (lightMode ? 3 : this.quality === 'cinematic' ? 10 : 7) *
          Math.max(0, Math.min(1, effectScale)),
      ),
    );
    // Keep the newest received hits visible even during crowded enemy volleys.
    const visible = b.explosions
      .filter(
        (e) =>
          time - e.bornAt <
            (e.kind === 'impact' ? (e.playerHit ? 1.2 : 0.6) : 5.5) &&
          Math.hypot(e.x - b.player.x, e.y - b.player.y) <
            (lightMode ? 800 : 1250),
      )
      .sort(
        (a, b) =>
          Number(!!a.playerHit) - Number(!!b.playerHit) ||
          a.bornAt - b.bornAt ||
          a.id - b.id,
      )
      .slice(-slots);
    let spriteCount = 0,
      fragmentCount = 0,
      brightest = 0;
    this.light.intensity = 0;
    this.light.diffuse.set(1, 0.42, 0.095);
    for (const e of visible) {
      const age = Math.max(0, time - e.bornAt),
        s = e.scale;
      if (e.kind === 'impact' && e.playerHit) {
        // A sharp armor strike: bright first, then quickly clear the live tank.
        const rand = seeded(e.id * 257 + 71);
        if (age < 0.16)
          this.puff(
            spriteCount++,
            e,
            age,
            3,
            0,
            0,
            2.05,
            (4.2 + age * 27) * s,
            (1 - age / 0.16) ** 1.4,
            e.id,
          );
        const fireCount = lightMode ? 2 : 3;
        for (let i = 0; i < fireCount; i++) {
          const angle = rand() * Math.PI * 2,
            offset = 5 + rand() * 11,
            duration = 0.34 + rand() * 0.14;
          if (age >= duration) continue;
          const growth = 1 - Math.exp(-age * 18);
          this.puff(
            spriteCount++,
            e,
            age,
            0,
            Math.cos(angle) * offset * growth * s,
            Math.sin(angle) * offset * growth * s,
            1.5 + age * 1.8 + i * 0.22,
            (1.35 + growth * 2.6) * s,
            Math.min(1, (duration - age) * 4.2) * 0.9,
            e.id * 3.1 + i * 8.7,
          );
        }
        const sparkCount = lightMode
          ? 5
          : this.quality === 'cinematic'
            ? 12
            : 9;
        for (let i = 0; i < sparkCount; i++) {
          const angle = ((i + rand() * 0.55) / sparkCount) * Math.PI * 2,
            speed = 85 + rand() * 95,
            duration = 0.3 + rand() * 0.22,
            lift = 1.3 + rand() * 2.2;
          if (age >= duration) continue;
          const travel = (7 + speed * age) * s,
            length = (0.6 + speed * 0.006) * s;
          const index = spriteCount++;
          this.puff(
            index,
            e,
            age,
            6,
            Math.cos(angle) * travel,
            Math.sin(angle) * travel,
            Math.max(0.18, 1.7 + lift * age - 4.9 * age * age),
            length,
            Math.min(1, (duration - age) * 8),
            e.id * 11.3 + i,
          );
          const spark = this.sprites[index];
          spark.rotation.z = angle;
          spark.scaling.y = (0.16 + 0.05 * s) * (1 - (age / duration) * 0.5);
        }
        if (age < 0.65)
          this.puff(
            spriteCount++,
            e,
            age,
            2,
            0,
            0,
            0.11,
            (2.8 + Math.sqrt(age) * 14) * s,
            (1 - age / 0.65) * 0.86,
            e.id * 4.7,
          );
        const smokeCount = lightMode ? 1 : 2;
        for (let i = 0; i < smokeCount; i++) {
          const t = age - 0.045 - i * 0.07;
          if (t < 0 || t >= 1.05) continue;
          this.puff(
            spriteCount++,
            e,
            t,
            1,
            (i === 0 ? -7 : 8) * s + t * 7,
            (i === 0 ? -4 : 5) * s,
            1.6 + t * 2.3,
            (1.8 + Math.sqrt(t) * 2.5) * s,
            Math.min(1, t * 12) * (1 - t / 1.05) * 0.55,
            e.id * 7.3 + i * 13.1,
          );
        }
        const energy = Math.max(0, 1 - age / 0.27) ** 2 * s * 1.5;
        if (!lightMode && energy > brightest) {
          brightest = energy;
          this.light.position.copyFrom(worldPosition(e.x, e.y, 3));
          this.light.intensity = energy * 95;
          this.light.range = 20 + s * 10;
          this.light.diffuse.set(
            e.weapon === 5 ? 0.24 : e.weapon === 3 ? 0.68 : 1,
            e.weapon === 5 ? 0.75 : e.weapon === 3 ? 0.25 : 0.49,
            e.weapon === 5 || e.weapon === 3 ? 1 : 0.12,
          );
        }
        continue;
      }
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
      if (!masonry && age < 0.09) {
        this.puff(
          spriteCount++,
          e,
          age,
          3,
          0,
          0,
          1.7 * s,
          (3 + age * 58) * s,
          (1 - age / 0.09) ** 2,
          e.id,
        );
      }
      const fireCount = masonry ? 0 : lightMode ? 2 : small ? 3 : 5;
      for (let i = 0; i < fireCount; i++) {
        const angle = rand() * Math.PI * 2,
          offset = rand() * 18 * s;
        const duration = (small ? 0.32 : 0.5) + rand() * 0.24;
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
        const expansion = 1 - Math.exp(-t * 1.35);
        this.puff(
          spriteCount++,
          e,
          t,
          1,
          (Math.cos(angle) * drift * expansion + t * 7) * s,
          Math.sin(angle) * drift * expansion * s,
          (0.9 + (masonry ? 1.5 : 4.6) * (1 - Math.exp(-t * 0.55)) + i * 0.38) *
            s,
          (2.2 + 4.8 * expansion + 0.7 * Math.sqrt(t)) * s,
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
      if (age < 2.2) {
        const dustCount = lightMode ? 2 : 5;
        for (let i = 0; i < dustCount; i++) {
          const angle = (i / dustCount) * Math.PI * 2 + e.id;
          const travel = (1 - Math.exp(-age * 2)) * 65 * s;
          this.puff(
            spriteCount++,
            e,
            age,
            5,
            Math.cos(angle) * travel,
            Math.sin(angle) * travel,
            0.25 + age * 0.2,
            (2.4 + Math.sqrt(age) * 6) * s,
            Math.min(1, age * 15) * (1 - age / 2.2) * 0.48,
            e.id * 13 + i,
          );
        }
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
          : age < 0.12
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
        this.light.diffuse.set(1, 0.42, 0.095);
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
