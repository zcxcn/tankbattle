// Web-only imports: these recordings never enter the frozen Android bundle.
import cannon01 from '../web/audio/combat/cannon-01.wav';
import cannon02 from '../web/audio/combat/cannon-02.wav';
import cannon03 from '../web/audio/combat/cannon-03.wav';
import mg from '../web/audio/combat/mg-fire.wav';
import shotgun from '../web/audio/combat/weapon-shotgun.wav';
import rail from '../web/audio/combat/weapon-rail.wav';
import grenade from '../web/audio/combat/weapon-grenade.wav';
import cryo from '../web/audio/combat/weapon-cryo.wav';
import rocket from '../web/audio/combat/rocket-launch.wav';
import explosion01 from '../web/audio/combat/explosion-heavy-01.wav';
import explosion02 from '../web/audio/combat/explosion-heavy-02.wav';
import armor01 from '../web/audio/combat/impact-armor-01.wav';
import armor02 from '../web/audio/combat/impact-armor-02.wav';
import ricochet01 from '../web/audio/combat/ricochet-01.wav';
import ricochet02 from '../web/audio/combat/ricochet-02.wav';
import emp from '../web/audio/combat/emp-pulse.wav';
import pickup from '../web/audio/combat/pickup-confirm.wav';
import engine from '../web/audio/combat/track-engine.wav';
import tracks from '../web/audio/combat/track-treads.wav';

// Cannon and the two movement loops take priority during the first load.
export const COMBAT_AUDIO_ASSETS = {
  cannon01,
  engine,
  tracks,
  cannon02,
  cannon03,
  mg,
  explosion01,
  armor01,
  rocket,
  shotgun,
  grenade,
  rail,
  cryo,
  explosion02,
  armor02,
  ricochet01,
  ricochet02,
  emp,
  pickup,
};
export type CombatClip = keyof typeof COMBAT_AUDIO_ASSETS;

export const WEAPON_CLIPS: readonly (readonly CombatClip[])[] = [
  // One field-recorded tank report; the alternate artillery take is much brighter.
  ['cannon01'],
  ['mg'],
  ['shotgun'],
  ['rail'],
  ['grenade'],
  ['cryo'],
  ['rocket'],
];
