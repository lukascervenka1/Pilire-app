"""Check the exported dog clips, including actual skinned muzzle/paw positions."""
from pathlib import Path
import numpy as np
from author_dog_companion import Rig


def sample(rig, clip, time):
    translations, rotations = rig.t.copy(), rig.q.copy()
    for channel in clip['channels']:
        sampler = clip['samplers'][channel['sampler']]
        times = rig.acc(sampler['input'])[:, 0]
        values = rig.acc(sampler['output'])
        value = np.array([np.interp(time, times, values[:, k]) for k in range(values.shape[1])])
        node = channel['target']['node']
        if channel['target']['path'] == 'translation':
            translations[node] = value
        else:
            rotations[node] = value / np.linalg.norm(value)
    return translations, rotations


for name in ['shiba', 'husky']:
    rig = Rig(Path('Pilire/Animals3D') / (name + '.gltf'), reset_generated=False)
    clips = {c['name']: c for c in rig.d['animations']}
    assert len(clips) == len(rig.d['animations']), 'Duplicate animation names'
    eat, fed = clips['Companion_Eat'], clips['Companion_Fed']
    mask = []
    for node in rig.nodes:
        if 'mesh' not in node:
            continue
        skin = rig.d['skins'][node['skin']]
        head_joint = skin['joints'].index(rig.names['Head'])
        for primitive in rig.d['meshes'][node['mesh']]['primitives']:
            attributes = primitive['attributes']
            joints = rig.acc(attributes['JOINTS_0']).astype(int)
            weights = rig.acc(attributes['WEIGHTS_0'])
            mask.extend(np.sum(np.where(joints == head_joint, weights, 0), axis=1) > .4)
    mask = np.array(mask)
    nose = mask & (rig.original[:, 2] > rig.original[mask, 2].max() - .12)
    muzzle_heights, tail_x = [], []
    for time in np.linspace(0, 6.4, 155):
        t, q = sample(rig, eat, time)
        vertices = rig.vertices(t, q)
        world = rig.world(t, q)
        assert (vertices[:, 1].min() - rig.floor) * rig.scale >= -.004
        for paw in ['IKFrontLeg.L', 'IKFrontLeg.R', 'IKBackLeg.L', 'IKBackLeg.R']:
            index = rig.names[paw]
            assert abs(world[index][1, 3] - rig.bind[index][1, 3]) * rig.scale < .002
        chest = rig.names['Torso3']
        assert world[chest][1, 3] > rig.bind[chest][1, 3] * .65, 'Dog collapsed instead of standing'
        if 1.3 < time < 5.1:
            muzzle = (vertices[nose].mean(axis=0) - [0, rig.floor, 0]) * rig.scale
            assert .025 < muzzle[1] < .060, ('Muzzle misses bowl height', muzzle)
            assert abs(muzzle[2] - (.30 if name == 'husky' else .28)) < .04
            muzzle_heights.append(muzzle[1])
    for time in np.linspace(0, 2.8, 70):
        t, q = sample(rig, fed, time)
        world = rig.world(t, q)
        tail = rig.names['Tail3' if name == 'shiba' else 'Tail6']
        tail_x.append(world[tail][0, 3] * rig.scale)
    assert np.ptp(tail_x) > .04, 'Happy tail response is not visible'
    for clip, duration in [(eat, 6.4), (fed, 2.8)]:
        start = rig.vertices(*sample(rig, clip, 0))
        end = rig.vertices(*sample(rig, clip, duration))
        assert np.max(np.abs(start - end)) * rig.scale < .001, 'Clip does not return to standing'
    print(name, 'PASS: four planted paws, standing chest, muzzle at bowl, visible wag and standing endpoints;',
          'muzzle height', tuple(round(float(x), 3) for x in [min(muzzle_heights), max(muzzle_heights)]))
