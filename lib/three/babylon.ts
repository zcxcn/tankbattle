// Import engine features explicitly so unrelated loaders, XR and WebGPU systems
// are not included in the browser's initial 3D bundle.
export { Engine } from '@babylonjs/core/Engines/engine.js';
export type { AbstractEngine } from '@babylonjs/core/Engines/abstractEngine.js';
export { Scene } from '@babylonjs/core/scene.js';
export {
  Vector3,
  Matrix,
  Quaternion,
} from '@babylonjs/core/Maths/math.vector.js';
export { Color3, Color4 } from '@babylonjs/core/Maths/math.color.js';
export { UniversalCamera } from '@babylonjs/core/Cameras/universalCamera.js';
export { Mesh } from '@babylonjs/core/Meshes/mesh.js';
export { MeshBuilder } from '@babylonjs/core/Meshes/meshBuilder.js';
export { TransformNode } from '@babylonjs/core/Meshes/transformNode.js';
export { VertexData } from '@babylonjs/core/Meshes/mesh.vertexData.js';
export type { Material } from '@babylonjs/core/Materials/material.js';
export { PBRMaterial } from '@babylonjs/core/Materials/PBR/pbrMaterial.js';
export { StandardMaterial } from '@babylonjs/core/Materials/standardMaterial.js';
export { ShaderMaterial } from '@babylonjs/core/Materials/shaderMaterial.js';
export { Texture } from '@babylonjs/core/Materials/Textures/texture.js';
export { RawTexture } from '@babylonjs/core/Materials/Textures/rawTexture.js';
export { CubeTexture } from '@babylonjs/core/Materials/Textures/cubeTexture.js';
export { ImageProcessingConfiguration } from '@babylonjs/core/Materials/imageProcessingConfiguration.js';
export { PointLight } from '@babylonjs/core/Lights/pointLight.js';
export { DirectionalLight } from '@babylonjs/core/Lights/directionalLight.js';
export { HemisphericLight } from '@babylonjs/core/Lights/hemisphericLight.js';
export { ShadowGenerator } from '@babylonjs/core/Lights/Shadows/shadowGenerator.js';
export { DefaultRenderingPipeline } from '@babylonjs/core/PostProcesses/RenderPipeline/Pipelines/defaultRenderingPipeline.js';
import '@babylonjs/core/Culling/ray.js';
import '@babylonjs/core/Meshes/thinInstanceMesh.js';

export { DynamicTexture } from '@babylonjs/core/Materials/Textures/dynamicTexture.js';
