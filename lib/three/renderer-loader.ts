/** Share one import across menu intent and deployment; failed downloads can retry. */
let rendererModule: Promise<typeof import('./renderer3d')> | undefined;
export function preloadRenderer() {
  return (rendererModule ??= import('./renderer3d').catch((error) => {
    rendererModule = undefined;
    throw error;
  }));
}
