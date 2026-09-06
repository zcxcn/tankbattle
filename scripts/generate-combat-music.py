#!/usr/bin/env python3
"""Three original high-energy game battle loops. Python 3 + NumPy only.

No external samples or existing melodies. Deterministic additive/FM synthesis,
filtered noise percussion, circular event tails and circular stereo reverbs.
Run `python3 scripts/generate-combat-music.py` to render all three WAV files plus metrics.
"""
from pathlib import Path
import json
import wave
import numpy as np

SR = 32000
OUT = Path(__file__).resolve().parent.parent / "public" / "music"
OUT.mkdir(parents=True, exist_ok=True)


def frequency(note):
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


class Score:
    def __init__(self, bpm, seed):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.frames = round(32 * self.beat * SR)
        self.duration = self.frames / SR
        self.rng = np.random.default_rng(seed)
        self.drums = np.zeros((self.frames, 2))
        self.bass = np.zeros_like(self.drums)
        self.music = np.zeros_like(self.drums)
        self.air = np.zeros_like(self.drums)

    def time(self, seconds):
        return np.arange(round(seconds * SR), dtype=float) / SR

    def env(self, t, gate, attack=.006, release=.12, decay=0.0):
        a = np.sin(np.pi * .5 * np.minimum(t / attack, 1)) ** 2
        r = np.cos(np.pi * .5 * np.clip((t - gate) / release, 0, 1)) ** 2
        return a * r * np.exp(-decay * t)

    def noise(self, t, center, width):
        f = np.fft.rfftfreq(len(t), 1.0 / SR)
        response = np.exp(-.5 * ((f - center) / width) ** 2)
        raw = self.rng.normal(size=len(t))
        x = np.fft.irfft(np.fft.rfft(raw) * response, n=len(t))
        return x / max(1e-9, np.std(x))

    def put(self, bus, at, signal, gain=1.0, pan=0):
        offset = round(at * self.beat * SR)
        idx = (offset + np.arange(len(signal))) % self.frames
        angle = (np.clip(pan, -1, 1) + 1) * np.pi / 4
        weights = np.array([np.cos(angle), np.sin(angle)])
        bus[idx] += signal[:, None] * gain * weights

    def filter(self, x, lowpass=6500, highpass=24, order=3):
        f = np.fft.rfftfreq(len(x), 1.0 / SR)
        r = 1 / np.sqrt(1 + (f / lowpass) ** (2 * order))
        if highpass:
            r *= 1 - np.exp(-(f / highpass) ** 4)
        r[0] = 0
        return np.fft.irfft(np.fft.rfft(x, axis=0) * r[:, None],
                            n=len(x), axis=0)

    def kick(self, heavy=1.0):
        t = self.time(.48)
        phase = 2*np.pi*(46*t + 94*.019*(1-np.exp(-t/.019)))
        body = (np.sin(phase)+.15*np.sin(2*phase)*np.exp(-t/.04))
        body *= np.exp(-t/.12)
        attack = self.noise(t,950,650)*.10*np.exp(-t/.009)
        return (body+attack)*self.env(t,.31,.002,.17)*heavy

    def snare(self, heavy=1.0):
        t = self.time(.33)
        shell = (.47*np.sin(2*np.pi*177*t)+.13*np.sin(2*np.pi*273*t))
        shell *= np.exp(-t/.055)
        skin = self.noise(t,2100,1050)*.60*np.exp(-t/.055)
        return (shell+skin)*self.env(t,.19,.0018,.14)*heavy

    def tom(self, note=39, heavy=1.0):
        t = self.time(.73)
        f = frequency(note)
        p = 2*np.pi*(f*t + f*.20*.04*(1-np.exp(-t/.04)))
        body=(np.sin(p)+.28*np.sin(1.47*p)+.16*np.sin(2.11*p))
        body *= np.exp(-t/.20)
        head = self.noise(t,660,420)*.20*np.exp(-t/.045)
        return (body+head)*self.env(t,.49,.0025,.24)*heavy

    def metal(self, pitch=210):
        t = self.time(.36)
        modes = [(1,.55),(1.39,.24),(2.04,.14),(2.63,.075),(3.51,.045)]
        x = sum(a*np.sin(2*np.pi*pitch*ratio*t)*np.exp(-t/(.075/ratio))
                for ratio,a in modes)
        x += self.noise(t,1700,620)*.11*np.exp(-t/.018)
        return x*self.env(t,.17,.002,.19)

    def hat(self, open_hat=False):
        dur = .22 if open_hat else .105
        t = self.time(dur)
        x = self.noise(t,4700,1000)
        x *= np.exp(-t/(.044 if open_hat else .014))
        return x*self.env(t,dur*.46,.002,dur*.54)

    def low_synth(self, note, beats=.4, bite=.65):
        gate = beats*self.beat
        t = self.time(gate+.09)
        p = 2*np.pi*frequency(note)*t
        # Smooth, warm harmonic body, with a transient opening of the filter.
        x = .76*np.sin(p + bite*.14*np.sin(p)*np.exp(-7*t))
        for h,a in [(2,.32),(3,.17),(4,.09),(5,.045),(6,.02)]:
            x += a*np.sin(h*p+.1*h)*(.28+.72*np.exp(-t*9))
        return x*self.env(t,gate,.008,.09,.42)

    def drive_lead(self, note, beats=.35, strength=1.0):
        gate = beats*self.beat
        t = self.time(gate+.14)
        x = np.zeros(len(t))
        f=frequency(note)
        for detune,weight in [(-5.5,.25),(0,.5),(5.5,.25)]:
            p = 2*np.pi*f*2**(detune/1200)*t
            p += .025*np.sin(2*np.pi*5.3*t)
            p += .24*np.sin(2*p)*np.exp(-10*t)
            for h,a in [(1,.75),(2,.31),(3,.15),(4,.068),(5,.024)]:
                x += weight*a*np.sin(h*p+.19*h)
        return x*self.env(t,gate,.008,.14,.72)*strength

    def brass(self, note, beats=.75):
        gate=beats*self.beat
        t=self.time(gate+.24)
        f=frequency(note)
        p=2*np.pi*f*t + .017*np.sin(2*np.pi*4.8*t)
        x=np.sin(p)+.36*np.sin(2*p)+.19*np.sin(3*p)+.075*np.sin(4*p)
        x += .08*np.sin(2*np.pi*f*1.003*t+.3)
        return x*self.env(t,gate,.024,.24,.22)*.75

    def staccato(self,note,beats=.23):
        gate=beats*self.beat
        t=self.time(gate+.14)
        f=frequency(note)
        x=np.zeros(len(t))
        for cents,level in [(-6,.3),(0,.4),(7,.3)]:
            p=2*np.pi*f*2**(cents/1200)*t
            x+=level*(.8*np.sin(p)+.30*np.sin(2*p+.2)+.16*np.sin(3*p)
                      +.05*np.sin(5*p))
        x+=self.noise(t,1700,720)*.009
        return x*self.env(t,gate,.008,.14,3.5)

    def pad(self,note,beats=4):
        gate=beats*self.beat
        t=self.time(gate+.50)
        f=frequency(note)
        x=np.zeros(len(t))
        for cents,weight in [(-7,.25),(0,.5),(7,.25)]:
            p=2*np.pi*f*2**(cents/1200)*t
            x+=weight*(np.sin(p)+.20*np.sin(2*p+.2)+.07*np.sin(3*p+.4))
        return x*self.env(t,gate,.12,.50)*(.85+.15*np.sin(2*np.pi*.7*t))

    def sweep(self, beats=4):
        t=self.time(beats*self.beat)
        x=self.noise(t,1250,550)
        return x*np.sin(np.pi*t/(beats*self.beat))**4

    def hall(self,x,wet=.12):
        src=self.filter(x,2700,130,2)
        room=np.zeros_like(x)
        for i,(sec,amp) in enumerate([(.037,.31),(.061,.28),(.103,.23),
                (.157,.19),(.223,.15),(.307,.12),(.421,.09),(.557,.068),
                (.731,.048),(.947,.033),(1.211,.021)]):
            tap=np.roll(src,round(sec*SR),axis=0)
            room+=amp*(tap[:,::-1] if i%2 else tap)
        return x+wet*room

    def render(self,name,title,style):
        # A little tempo delay gives melody width without washing out drums.
        melodic=self.hall(self.music,.15)
        melodic+=np.roll(self.filter(self.music,2300,250),
                        round(.75*self.beat*SR),axis=0)[:,::-1]*.12
        mix=self.hall(self.drums,.055)+self.bass+melodic+self.hall(self.air,.20)
        mix=self.filter(mix,6800,27)
        # Soft saturation provides energy; a final gentle filter limits grit.
        mix=np.tanh(mix*1.65)
        mix=self.filter(mix,7100,24)
        mix-=mix.mean(axis=0)
        mix*=.88/np.max(np.abs(mix))
        pcm=np.rint(mix*32767).astype('<i2')
        path=OUT/(name+'.wav')
        with wave.open(str(path),'wb') as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        decoded=pcm.astype(float)/32768
        d=np.diff(decoded,axis=0)
        seam=decoded[0]-decoded[-1]
        rms=float(np.sqrt(np.mean(decoded**2)))
        return dict(name=name,title=title,style=style,path=str(path),bpm=self.bpm,
            bars=8,time_signature='4/4',duration_seconds=self.duration,
            sample_rate=SR,channels=2,bits_per_sample=16,frames=self.frames,
            bytes=path.stat().st_size,peak=float(np.max(np.abs(decoded))),rms=rms,
            rms_dbfs=float(20*np.log10(rms)),
            loop_seam_difference_lr=seam.tolist(),
            loop_seam_abs_max=float(np.max(np.abs(seam))),
            adjacent_sample_difference_rms=float(np.sqrt(np.mean(d*d))),
            adjacent_sample_difference_max=float(np.max(np.abs(d))),
            dc_lr=decoded.mean(axis=0).tolist(),
            clipped_samples=int(np.sum(np.abs(pcm.astype(np.int32))>=32767)))


def industrial():
    s=Score(136,860701)
    # D minor with a dark mechanical, syncopated motif.
    roots=[38,38,34,36,38,41,31,33]
    chords=[[50,57,62,65],[50,57,62,65],[46,53,58,62],[48,55,60,64],
            [50,57,62,65],[48,53,57,60],[43,50,58,62],[45,52,57,61]]
    motifs=[[62,62,65,64,62,69,65,61],[62,65,69,67,65,64,62,60],
            [62,65,62,58,65,62,60,58],[60,64,67,64,62,60,59,60],
            [62,62,65,69,72,69,65,64],[65,69,72,69,67,65,64,60],
            [62,67,65,62,58,62,65,67],[61,64,69,67,64,61,64,61]]
    for bar in range(8):
        o=bar*4
        root=roots[bar]
        for step,gain in [(0,.67),(.75,.37),(1.5,.47),(2,.58),(2.75,.32),(3.5,.49)]:
            s.put(s.drums,o+step,s.kick(),gain)
        for step in [1,3]:
            s.put(s.drums,o+step,s.snare(),.35)
            s.put(s.drums,o+step,s.metal(185 if step==1 else 221),.12, -.18)
        for i in range(16):
            if i%4!=0:
                s.put(s.drums,o+i*.25,s.hat(),.033 if i%2==0 else .016,
                      .25 if i%2 else -.22)
        for step,note,gain in [(.5,40,.18),(2.5,44,.17),(3.75,38,.22)]:
            s.put(s.drums,o+step,s.tom(note),gain,.18)
        for i in range(8):
            note=root+(12 if i in [3,6] else 0)
            s.put(s.bass,o+i*.5,s.low_synth(note,.37),.26 if i%2==0 else .21)
            s.put(s.music,o+i*.5,s.drive_lead(motifs[bar][i],.32),
                  .120 if i%2==0 else .094,-.14)
        for step in [0,1.75,3.25]:
            for j,note in enumerate(chords[bar][:3]):
                s.put(s.music,o+step,s.brass(note,.38),.055,[-.3,0,.3][j])
        for j,note in enumerate(chords[bar][1:]):
            s.put(s.air,o,s.pad(note),.031,[-.6,0,.6][j])
        if bar in [3,7]:
            for step,note in [(3,45),(3.25,43),(3.5,40),(3.75,38)]:
                s.put(s.drums,o+step,s.tom(note),.13,(step-3.5)*.8)
            s.put(s.air,o,s.sweep(),.018)
    return s.render('industrial-war','钢铁风暴','工业战争 / 136 BPM')


def chase():
    s=Score(160,860702)
    # F-sharp minor. Relentless subdivisions, octave bass and a racing hook.
    roots=[30,38,40,37,30,33,38,37]
    triads=[[54,57,61],[50,54,57],[52,56,59],[49,53,56],
            [54,57,61],[57,61,64],[50,54,57],[49,53,56]]
    motifs=[[66,69,73,71,69,68,66,73],[66,69,74,73,69,66,64,66],
            [68,71,76,73,71,68,66,64],[65,68,73,71,68,65,61,65],
            [66,69,73,78,76,73,71,69],[69,73,76,73,71,69,68,64],
            [66,69,74,73,69,66,64,62],[65,68,73,71,68,65,68,65]]
    for bar in range(8):
        o=bar*4
        for step in [0,1,2,3]:
            s.put(s.drums,o+step,s.kick(),.62)
        for step in [1,3]:
            s.put(s.drums,o+step,s.snare(),.28)
        for step in [.5,1.5,2.5,3.5]:
            s.put(s.drums,o+step,s.hat(True),.067,.14)
        for i in range(16):
            if i%2:
                s.put(s.drums,o+i*.25,s.hat(),.025,-.21)
            note=roots[bar]+(12 if i%4==3 else 0)
            gain=.19 if i%4 else .11
            s.put(s.bass,o+i*.25,s.low_synth(note,.16,.8),gain)
            chord=triads[bar]
            pitch=chord[[0,1,2,1,2,1,0,2][i%8]]+12
            s.put(s.music,o+i*.25,s.staccato(pitch,.15),.045,
                  -.42 if i%2 else .42)
        for i,note in enumerate(motifs[bar]):
            s.put(s.music,o+i*.5,s.drive_lead(note,.34),.103)
        for j,note in enumerate(triads[bar]):
            s.put(s.air,o,s.pad(note),.035,[-.65,0,.65][j])
        if bar%2:
            for step,gain in [(3.5,.11),(3.75,.085)]:
                s.put(s.drums,o+step,s.snare(),gain)
        if bar in [3,7]:
            s.put(s.air,o,s.sweep(),.018)
            s.put(s.drums,o+3.75,s.tom(44),.17,.2)
    return s.render('electronic-pursuit','极速追击','高速电子追击 / 160 BPM')


def epic():
    s=Score(144,860703)
    # C minor. Heavy cinematic drums, urgent strings and low brass calls.
    roots=[36,32,39,34,36,32,29,31]
    chords=[[48,55,60,63],[44,51,56,60],[46,51,55,58],[46,53,58,62],
            [48,55,60,63],[44,51,56,60],[41,48,56,60],[43,50,55,59]]
    call=[[60,63,67,65],[60,63,68,67],[63,67,70,67],[62,65,70,68],
          [60,67,72,70],[68,67,63,60],[65,68,72,68],[67,65,62,59]]
    for bar in range(8):
        o=bar*4
        for step,gain in [(0,.70),(1.5,.41),(2,.62),(3.25,.38)]:
            s.put(s.drums,o+step,s.kick(),gain)
        for step,note,gain,pan in [(0,36,.25,-.1),(.75,43,.21,.35),
                (1.25,40,.18,-.3),(1.75,45,.17,.28),(2.5,43,.23,-.35),
                (3,38,.30,.18),(3.5,40,.24,-.22),(3.75,45,.13,.25)]:
            s.put(s.drums,o+step,s.tom(note),gain,pan)
        for step in [1,3]:
            s.put(s.drums,o+step,s.snare(),.25)
        for step in [.5,1.5,2.5,3.5]:
            s.put(s.drums,o+step,s.metal(140),.035,-.2)
        # Bowed octave pattern with accents; no thin high-frequency saw lead.
        for i in range(16):
            j=[0,2,1,2,0,3,2,1][i%8]
            note=chords[bar][j]+12
            s.put(s.music,o+i*.25,s.staccato(note,.18),
                  .096 if i%4==0 else .054, -.5 if i%2 else .5)
        for step in [0,1,2,3]:
            s.put(s.bass,o+step,s.low_synth(roots[bar],.70,.4),.28)
        for i,note in enumerate(call[bar]):
            at=[0,.75,2,3][i]
            length=[.60,.85,.70,.70][i]
            s.put(s.music,o+at,s.brass(note,length),.13)
            s.put(s.music,o+at,s.brass(note-12,length),.065,-.12)
        for j,note in enumerate(chords[bar]):
            s.put(s.air,o,s.pad(note),.029,[-.7,-.3,.3,.7][j])
        if bar in [3,7]:
            for step,note in [(3,48),(3.25,45),(3.5,43),(3.75,38)]:
                s.put(s.drums,o+step,s.tom(note),.19,(step-3.4)*.8)
            s.put(s.air,o,s.sweep(),.013)
    return s.render('epic-siege','决战重围','史诗重鼓 / 144 BPM')


if __name__=='__main__':
    report={'composer':'Original procedural composition and synthesis',
            'loop_method':'Circular event tails, delays and frequency-domain filters',
            'tracks':[]}
    for make in [industrial,chase,epic]:
        track=make()
        report['tracks'].append(track)
        print(json.dumps(track,ensure_ascii=False,indent=2),flush=True)
    (OUT.parent.parent/'outputs/music/combat-analysis.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
