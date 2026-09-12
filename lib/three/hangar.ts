import { assetUrl } from '../asset-url';
import {
  FramePacer,
  isMobileDevice,
  deviceState,
  resolutionScale,
} from '../performance';
import {
  Engine,
  Scene,
  UniversalCamera,
  Vector3,
  Color3,
  Color4,
  CubeTexture,
  HemisphericLight,
  DirectionalLight,
  PointLight,
  ShadowGenerator,
  DefaultRenderingPipeline,
  ImageProcessingConfiguration,
  MeshBuilder,
  TransformNode,
  type Mesh,
} from './babylon';
import { buildTank, box, type TankModel } from './tank-model';
import { createMaterials, pbr, type Materials } from './materials';
export class Hangar {
  engine: Engine;
  scene: Scene;
  camera: UniversalCamera;
  model: TankModel;
  materials: Materials;
  shadow: ShadowGenerator;
  disposed = false;
  private elapsed = 0;
  private active = true;
  private mobile = isMobileDevice();
  private dirty = true;
  private pacer = new FramePacer();
  private chassis: number;
  private level: number;
  private contact: Mesh;
  constructor(canvas: HTMLCanvasElement, chassis: number, level = 1) {
    this.chassis = chassis;
    this.level = level;
    this.engine = new Engine(
      canvas,
      true,
      { powerPreference: 'low-power', preserveDrawingBuffer: false },
      false,
    );
    this.engine.setHardwareScalingLevel(
      this.mobile
        ? resolutionScale(
            canvas.clientWidth,
            canvas.clientHeight,
            window.devicePixelRatio,
          )
        : 1,
    );
    const scene = (this.scene = new Scene(this.engine));
    scene.useRightHandedSystem = true;
    scene.clearColor = new Color4(0.055, 0.069, 0.058, 1);
    scene.fogMode = Scene.FOGMODE_EXP2;
    scene.fogDensity = 0.014;
    scene.fogColor = new Color3(0.045, 0.061, 0.049);
    scene.skipPointerMovePicking = true;
    this.camera = new UniversalCamera(
      'garage-camera',
      new Vector3(8.8, 5.7, 12.5),
      scene,
    );
    this.camera.inputs.clear();
    this.camera.fov = 0.67;
    this.camera.minZ = 0.1;
    this.camera.maxZ = 120;
    this.camera.setTarget(new Vector3(-1.3, 1, 0));
    scene.activeCamera = this.camera;
    this.materials = createMaterials(scene, true, this.mobile);
    scene.environmentTexture = CubeTexture.CreateFromPrefilteredData(
      assetUrl('/environment.env'),
      scene,
    );
    scene.environmentIntensity = 0.6;
    const ambient = new HemisphericLight(
      'garage-ambient',
      new Vector3(0, 1, 0),
      scene,
    );
    ambient.intensity = 0.5;
    ambient.diffuse = new Color3(0.64, 0.72, 0.77);
    ambient.groundColor = new Color3(0.2, 0.22, 0.18);
    const key = new DirectionalLight(
      'garage-key',
      new Vector3(-0.3, -1, -0.5),
      scene,
    );
    key.position.set(7, 13, 7);
    key.intensity = 2.65;
    key.diffuse = new Color3(1, 0.93, 0.81);
    this.shadow = new ShadowGenerator(1024, key);
    key.autoUpdateExtends = false;
    key.orthoLeft = key.orthoBottom = -12;
    key.orthoRight = key.orthoTop = 12;
    key.shadowMinZ = 1;
    key.shadowMaxZ = 45;
    this.shadow.usePercentageCloserFiltering = true;
    this.shadow.filteringQuality = ShadowGenerator.QUALITY_MEDIUM;
    this.shadow.bias = 0.001;
    this.shadow.normalBias = 0.025;
    const rim = new PointLight(
      'garage-cool-rim',
      new Vector3(-6, 5, -5),
      scene,
    );
    rim.diffuse = new Color3(0.4, 0.65, 0.72);
    rim.intensity = 65;
    rim.range = 20;
    const floor = MeshBuilder.CreateGround(
      'workshop-floor',
      { width: 60, height: 60 },
      scene,
    );
    floor.material = this.materials.ground;
    floor.receiveShadows = true;
    const workshop = new TransformNode('workshop', scene),
      dark = pbr(scene, 'workshop-dark-metal', '#24302a', 0.63, 0.45);
    for (const x of [-9, 9]) {
      box(
        scene,
        'workshop-column',
        [0.7, 13, 0.7],
        [x, 6.5, -5],
        this.materials.steel,
        workshop,
      );
      box(
        scene,
        'workshop-roof-beam',
        [0.6, 0.6, 30],
        [x, 10, -5],
        this.materials.steel,
        workshop,
      );
    }
    box(scene, 'distant-back-wall', [32, 12, 0.5], [0, 6, -14], dark, workshop);
    for (let x = -15; x < 16; x += 2) {
      box(
        scene,
        'ribbed-wall',
        [0.12, 11, 0.15],
        [x, 5.5, -13.7],
        this.materials.steel,
        workshop,
      );
    }
    for (const x of [-8, -3, 2, 7]) {
      box(
        scene,
        'overhead-strip-light',
        [3.2, 0.08, 0.2],
        [x, 7, -5],
        this.materials.lamp,
        workshop,
      );
    }
    for (let i = 0; i < 8; i++)
      box(
        scene,
        'service-pit-marking',
        [0.12, 0.009, 0.6],
        [-4, 0.021, -3.1 + i * 0.9],
        this.materials.marking,
        workshop,
      );
    box(
      scene,
      'maintenance-track',
      [0.1, 0.035, 13],
      [-3, 0.04, 0],
      this.materials.edges,
      workshop,
    );
    box(
      scene,
      'maintenance-track',
      [0.1, 0.035, 13],
      [3, 0.04, 0],
      this.materials.edges,
      workshop,
    );
    for (let i = 0; i < 4; i++)
      box(
        scene,
        'supply-crate',
        [1.4, 0.8, 1.2],
        [-7 + i * 1.6, 0.4, -7],
        this.materials.armor,
        workshop,
      );
    this.model = buildTank(scene, this.materials, chassis, false, false, level);
    this.model.root.position.x = 0.9;
    this.model.root.scaling.setAll(1.13);
    this.model.body.rotation.y = -0.48;
    this.model.turret.rotation.y = -0.76;
    this.contact = MeshBuilder.CreateGround(
      'garage-vehicle-contact',
      { width: 4.5 * 1.13, height: 5.2 * 1.13 },
      scene,
    );
    this.contact.position.set(0.9, 0.018, 0);
    this.contact.material = this.materials.contact;
    this.contact.isPickable = false;
    this.contact.rotation.y = this.model.body.rotation.y;
    for (const mesh of this.model.meshes) this.shadow.addShadowCaster(mesh);
    scene.imageProcessingConfiguration.toneMappingEnabled = true;
    scene.imageProcessingConfiguration.toneMappingType =
      ImageProcessingConfiguration.TONEMAPPING_ACES;
    scene.imageProcessingConfiguration.exposure = 1.08;
    scene.imageProcessingConfiguration.contrast = 1.04;
    if (!this.mobile) {
      const pipe = new DefaultRenderingPipeline(
        'garage-tonemapping',
        true,
        scene,
        [this.camera],
      );
      pipe.fxaaEnabled = true;
      pipe.bloomEnabled = true;
      pipe.bloomWeight = 0.12;
      pipe.bloomThreshold = 1.5;
    }
    if (this.mobile) key.shadowEnabled = false;
    void scene.whenReadyAsync().then(() => {
      this.dirty = true;
    });
  }
  setChassis(chassis: number, level = 1) {
    if (this.chassis === chassis && this.level === level) return;
    this.chassis = chassis;
    this.level = level;
    this.dirty = true;
    for (const mesh of this.model.meshes) this.shadow.removeShadowCaster(mesh);
    this.model.dispose();
    this.model = buildTank(
      this.scene,
      this.materials,
      chassis,
      false,
      false,
      level,
    );
    this.model.root.position.x = 0.9;
    this.model.root.scaling.setAll(1.13);
    this.model.body.rotation.y = -0.48;
    this.model.turret.rotation.y = -0.76;
    for (const mesh of this.model.meshes) this.shadow.addShadowCaster(mesh);
  }
  start() {
    this.engine.runRenderLoop(() => {
      if (
        this.disposed ||
        !this.active ||
        document.hidden ||
        deviceState.background
      )
        return;
      if (this.mobile && !this.dirty) return;
      if (!this.pacer.take(performance.now(), 20)) return;
      this.dirty = false;
      this.elapsed += Math.min(0.05, this.engine.getDeltaTime() / 1000);
      this.model.body.rotation.y = -0.48 + Math.sin(this.elapsed * 0.13) * 0.13;
      this.contact.rotation.y = this.model.body.rotation.y;
      this.model.turret.rotation.y =
        -0.76 + Math.sin(this.elapsed * 0.17) * 0.13;
      this.camera.position.x = 8.8 + Math.sin(this.elapsed * 0.09) * 0.35;
      this.camera.setTarget(new Vector3(-1.3, 1, 0));
      this.scene.render();
    });
  }
  setActive(active: boolean) {
    this.active = active;
    if (active) this.dirty = true;
  }
  resize() {
    if (!this.disposed) {
      const canvas = this.engine.getRenderingCanvas();
      if (this.mobile && canvas)
        this.engine.setHardwareScalingLevel(
          resolutionScale(
            canvas.clientWidth,
            canvas.clientHeight,
            window.devicePixelRatio,
          ),
        );
      this.engine.resize();
      this.dirty = true;
    }
  }
  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.engine.stopRenderLoop();
    this.scene.dispose();
    this.engine.dispose();
  }
}
