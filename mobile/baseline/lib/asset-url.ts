// A standalone Pages build supplies its mount path. Studio and Android use root.
declare const __GAME_BASE_PATH__: string | undefined;
export const GAME_BASE_PATH =
  typeof __GAME_BASE_PATH__ === 'undefined' ? '/' : __GAME_BASE_PATH__;
export function assetUrl(path: string) {
  return GAME_BASE_PATH + path.replace(/^\/+/, '');
}
