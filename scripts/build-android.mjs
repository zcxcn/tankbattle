import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const home = os.homedir();
async function existing(paths) {
  for (const item of paths.filter(Boolean)) {
    try {
      await fs.access(item);
      return item;
    } catch {}
  }
  return null;
}
const sdk = await existing([
  process.env.ANDROID_SDK_ROOT,
  process.env.ANDROID_HOME,
  path.join(home, 'Library/Android/sdk'),
  path.join(home, '.totoro/android'),
]);
const java = await existing([
  process.env.IRON_EMBERS_JAVA_HOME,
  process.env.JAVA_HOME,
  '/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home',
  path.join(
    home,
    '.gradle/jdks/eclipse_adoptium-17-aarch64-os_x.2/jdk-17.0.18+8/Contents/Home',
  ),
]);
let gradle = process.env.IRON_EMBERS_GRADLE;
if (!gradle) {
  const cache = path.join(home, '.gradle/wrapper/dists/gradle-8.14.3-bin');
  try {
    gradle = await existing(
      (await fs.readdir(cache)).map((v) =>
        path.join(cache, v, 'gradle-8.14.3/bin/gradle'),
      ),
    );
  } catch {}
}
if (!sdk || !java)
  throw new Error(
    'Android SDK 36 and JDK 17 required. Set ANDROID_SDK_ROOT and IRON_EMBERS_JAVA_HOME.',
  );
await fs.access('outputs/android-web/index.html');
const result = spawnSync(
  gradle || 'gradle',
  [
    ...(process.env.IRON_EMBERS_OFFLINE === '1' ? ['--offline'] : []),
    '--no-daemon',
    'assembleRelease',
  ],
  {
    cwd: 'android',
    stdio: 'inherit',
    env: {
      ...process.env,
      JAVA_HOME: java,
      ANDROID_HOME: sdk,
      ANDROID_SDK_ROOT: sdk,
    },
  },
);
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status || 1);
await fs.mkdir('outputs/android', { recursive: true });
await fs.copyFile(
  'android/app/build/outputs/apk/release/app-release.apk',
  'outputs/android/iron-embers-android.apk',
);
console.log('APK: outputs/android/iron-embers-android.apk');
