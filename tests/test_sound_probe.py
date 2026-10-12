import math
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import sound_probe as sp

HALF = sp.bits(0.5)
ONE = sp.bits(1.0)


def fake(frames):
    """Samples a conversion could have given: two normal floats per frame."""
    return [sp.bits((i % 7 + 1) / 8) for i in range(2 * frames)]


def catalog():
    """Converted waves a reference pass could have given: two samples per frame."""
    table, out = sp.waves(), {}
    for name, (frames, rate, size, channels, data, refusal) in table.items():
        if refusal is not None:
            out['wave', name] = refusal
        elif name == 'zero':
            out['wave', name] = None
        elif frames == 0 or channels == 0 or rate == 0:
            out['wave', name] = (0, [])
        elif (rate, size, channels) == (48000, 32, 2):
            out['wave', name] = (frames, list(data))
        else:
            out['wave', name] = (frames, fake(frames))
    for name in ('boom', 'buttonfx', 'sound', 'coin', 'tiny'):
        out['file', name] = (3, fake(3))
    for name in sp.FILE_ERRORS:
        out['file', name] = (0, [])
    return out


def run(*steps):
    model = sp.Model(catalog())
    tags = [model.step(step) for step in steps]
    return model, tags


class SoundModelTests(unittest.TestCase):
    def test_the_device_opens_at_full_volume_and_closes_to_zero(self):
        model, _ = run(('master', HALF), ('init',))
        self.assertEqual((model.ready, model.master, model.undefined), (True, ONE, False))
        model, _ = run(('init',), ('master', sp.bits(-1.0)), ('master', sp.NAN), ('close',), ('master', HALF), ('close',))
        self.assertEqual((model.ready, model.master, model.undefined), (False, HALF, False))
        model, _ = run(('init',), ('master', HALF), ('init',))
        self.assertEqual((model.master, model.undefined), (HALF, True))

    def test_a_sound_is_a_tracked_buffer_over_a_block(self):
        model, tags = run(('init',), ('load', 0, 'mono16'), ('load', 1, 'zero'), ('load', 2, 'noframes'), ('alias', 3, 0))
        self.assertEqual(tags, ['-'] * 5)
        self.assertEqual(model.sounds, [(1, 8, 48000, 32, 2), sp.ZERO, (2, 0, 48000, 32, 2), (3, 8, 48000, 32, 2)])
        self.assertEqual([(b['id'], b['block'], b['frames']) for b in model.buffers], [(1, 1, 8), (2, 0, 0), (3, 1, 8)])
        self.assertEqual((list(model.blocks), model.undefined), ([1], False))
        head = ',48000,48000,0,1,0,0,0,0,0,0,0,0,0,2166136261,s'
        self.assertEqual(model.state(), 'R1 M%d D0 S1,8,48000,32,2,1,0,1,1 S0,0,0,0,0,0,0,0,0 S2,0,48000,32,2,0,0,1,1 S3,8,48000,32,2,1,0,1,1 B1,1,8,%d,%d,0,0,0,%d%s B2,0,0,%d,%d,0,0,0,-%s B3,1,8,%d,%d,0,0,0,%d%s'
                         % (ONE, ONE, ONE, sp.fnv(fake(8)), head, ONE, ONE, head, ONE, ONE, sp.fnv(fake(8)), head))

    def test_stop_leaves_a_paused_buffer(self):
        model, _ = run(('init',), ('load', 0, 'mono16'), ('play', 0), ('pause', 0), ('stop', 0))
        self.assertEqual((model.buffers[0]['playing'], model.buffers[0]['paused']), (True, True))
        model.step(('resume', 0))
        model.step(('stop', 0))
        self.assertEqual((model.buffers[0]['playing'], model.buffers[0]['paused'], model.undefined), (False, False, False))

    def test_volume_pitch_and_pan(self):
        model, _ = run(('init',), ('load', 0, 'mono16'), ('volume', 0, sp.bits(-2.5)), ('pitch', 0, sp.bits(2.0)), ('pitch', 0, sp.bits(0.0)), ('pitch', 0, sp.NAN),
                       ('pan', 0, sp.bits(7.0)))
        self.assertEqual((model.buffers[0]['volume'], model.buffers[0]['pitch'], model.buffers[0]['pan'], model.undefined), (sp.bits(-2.5), sp.bits(2.0), ONE, False))
        model.step(('pan', 0, sp.bits(-7.0)))
        model.step(('pitch', 0, sp.bits(1e-5)))
        self.assertEqual((model.buffers[0]['pitch'], model.buffers[0]['pan'], model.undefined), (sp.bits(2.0), sp.bits(-1.0), True))

    def test_unload_frees_the_block_and_unload_alias_keeps_it(self):
        model, _ = run(('init',), ('load', 0, 'mono16'), ('alias', 1, 0), ('unalias', 1))
        self.assertEqual(([b['id'] for b in model.buffers], list(model.blocks), model.undefined), ([1], [1], False))
        model, _ = run(('init',), ('load', 0, 'mono16'), ('alias', 1, 0), ('unload', 1))
        self.assertEqual(([b['id'] for b in model.buffers], list(model.blocks), model.undefined), ([1], [], False))
        self.assertTrue(model.state().endswith(',x,48000,48000,0,1,0,0,0,0,0,0,0,0,0,2166136261,s'))
        model.step(('alias', 2, 0))
        self.assertEqual((model.sounds[2], model.undefined), (sp.ZERO, True))

    def test_update_writes_the_shared_block_and_stops(self):
        model, _ = run(('init',), ('load', 0, 'mono16'), ('alias', 1, 0), ('play', 0), ('play', 1), ('update', 0, 1, [7, 9]))
        self.assertEqual((model.blocks[1][:4], model.buffers[0]['playing'], model.buffers[1]['playing'], model.undefined), ([7, 9] + fake(8)[2:4], False, True, False))
        for step in (('update', 0, 9, [0] * 18), ('update', 0, 1, [1]), ('update', 0, 0xFFFFFFFF, [])):
            model, _ = run(('init',), ('load', 0, 'mono16'), ('play', 0), step)
            self.assertEqual((model.blocks[1], model.buffers[0]['playing'], model.undefined), (fake(8), True, True))

    def test_what_raylib_has_no_answer_for(self):
        for steps, tags in (((('load', 0, 'mono16'),), ['device']), ((('init',), ('load', 0, 'size24')), ['-', 'request']),
                            ((('init',), ('load', 0, 'nan')), ['-', 'data']), ((('init',), ('load', 0, 'hugerate')), ['-', 'unsupported']),
                            ((('init',), ('load', 0, 'mono16'), ('unload', 0), ('play', 0)), ['-'] * 4), ((('init',), ('alias', 1, 0)), ['-'] * 2),
                            ((('stop', 0),), ['-']), ((('init',), ('load', 0, 'mono16'), ('close',), ('pause', 0)), ['-'] * 4)):
            model, got = run(*steps)
            self.assertEqual((got, model.undefined), (tags, True), steps)
        model, got = run(('init',), ('file', 0, 'missing'), ('file', 1, 'text'), ('file', 2, 'other'), ('file', 3, 'tiny'), ('play', 0), ('unload', 1))
        self.assertEqual((got, model.undefined, model.sounds[:3]), (['-', 'file', 'header', 'unsupported', '-', '-', '-'], False, [sp.ZERO] * 3))
        with self.assertRaises(ValueError):
            run(('init',), ('load', 0, 'mono16'), ('play', 0), ('close',), ('init',))


def taps(buffer):
    return [sp.bits(v) for v in buffer['x0'] + buffer['x1']]


class SoundMixTests(unittest.TestCase):
    def words(self, *values):
        return [sp.bits(v) for v in values]

    def test_a_buffer_comes_out_one_frame_late_and_stops_at_its_end(self):
        model, _ = run(('init',), ('load', 0, 'five32'), ('play', 0))
        data = sp.waves()['five32'][4]
        level = [sp.bits(max(-1.0, min(1.0, sp.fl(word) * 0.6875))) for word in data]    # volume 1 at the center: 0.5*0.5*(3 - 0.25), then the clip
        self.assertEqual(model.mix(2), [0, 0] + level[:2])
        self.assertEqual((model.buffers[0]['cursor'], taps(model.buffers[0]), model.buffers[0]['playing']), (2, data[:4], True))
        self.assertEqual(model.mix(480), level[2:8] + [0] * 954)
        self.assertEqual((model.buffers[0]['cursor'], taps(model.buffers[0]), model.buffers[0]['playing']), (0, data[6:10], False))
        model.step(('play', 0))
        self.assertEqual(model.mix(1), [level[8], sp.bits(0.0)])

    def test_the_last_frame_of_an_odd_buffer_at_the_start_of_a_run(self):
        model, _ = run(('init',), ('load', 0, 'five32'), ('play', 0))
        self.assertEqual(len(model.mix(4)), 8)
        self.assertEqual((model.buffers[0]['cursor'], model.buffers[0]['playing']), (4, True))
        self.assertEqual(model.mix(1), [0, 0])
        self.assertEqual((model.buffers[0]['cursor'], model.buffers[0]['playing']), (0, False))
        model, _ = run(('init',), ('load', 0, 'long513'), ('play', 0))
        model.mix(600)
        self.assertEqual((model.buffers[0]['cursor'], model.buffers[0]['playing'], taps(model.buffers[0])), (0, False, model.blocks[1][2 * 510:2 * 512]))

    def test_levels_master_and_clip(self):
        model, _ = run(('init',), ('load', 0, 'five32'), ('play', 0), ('mix', 1), ('pan', 0, sp.bits(1.0)), ('volume', 0, sp.bits(2.0)))
        self.assertEqual(model.mix(1), self.words(0.0, -0.5))            # the first frame (0.5, -0.25): right only, at 2*0.5*1*(3 - 1)
        model.step(('master', sp.bits(4.0)))
        self.assertEqual(model.mix(1), self.words(0.0, -1.0))            # (1.5, -3.0): -6 by the level, -24 by the master, clipped
        model.step(('pan', 0, 0))
        model.step(('volume', 0, sp.bits(1.0)))
        model.step(('master', sp.bits(1.0)))
        self.assertEqual(model.mix(1), self.words(0.0859375, 0.515625))  # (0.125, 0.75) at the center: 0.6875 each

    def test_what_the_mixer_refuses(self):
        for steps in ((('mix', 1),), (('init',), ('mix', 0)), (('init',), ('mix', (1 << 20) + 1)),
                      (('init',), ('load', 0, 'noframes'), ('play', 0), ('mix', 1)), (('init',), ('master', sp.NAN), ('mix', 1)),
                      (('init',), ('load', 0, 'five32'), ('volume', 0, sp.NAN), ('play', 0), ('mix', 1)),
                      (('init',), ('default', 480), ('stream', 0, 48000, 8, 1025), ('play', 0), ('mix', 1))):
            model, _ = run(*steps)
            self.assertEqual((model.mixed, model.undefined), (None, True), steps)
        model, _ = run(('init',), ('load', 0, 'five32'), ('pitch', 0, sp.bits(2.0)), ('pitch', 0, sp.bits(0.9999999)), ('pitch', 0, sp.bits(1e9)), ('play', 0), ('mix', 1))
        self.assertEqual((model.mixed, model.undefined, model.buffers[0]['rate']), ([0, 0], False, 48000))

    def test_subnormals_are_zeros_in_the_callback(self):
        self.assertEqual([sp.bits(sp.fz(sp.fl(w))) for w in (0, 1, 0x80000001, 0x007FFFFF, 0x00800000, 0x7F800000, sp.bits(-0.0))],
                         [0, 0, 0x80000000, 0, 0x00800000, 0x7F800000, 0x80000000])
        self.assertEqual([sp.bits(v) for v in (sp.fmul(2.0 ** -126, 0.5), sp.fmul(2.0 ** -127, 4.0), sp.fadd(2.0 ** -127, 1.0), sp.fsub(1.5 * 2.0 ** -126, 2.0 ** -126),
                                               sp.fdiv(-(2.0 ** -126), 2.0))], [0, 0, ONE, 0, 0x80000000])
        model, _ = run(('init',), ('load', 0, 'tiny32'), ('play', 0), ('mix', 1), ('mix', 1))       # (0.5, 1e-40): the frame it holds
        self.assertEqual((model.mixed, model.undefined), ([sp.bits(0.5 * 0.6875), 0], False))
        model, _ = run(('init',), ('load', 0, 'five32'), ('volume', 0, 1), ('play', 0), ('mix', 2))  # a subnormal volume is silence
        self.assertEqual((model.mixed, model.undefined), ([0, 0, 0, 0], False))


class SoundPitchTests(unittest.TestCase):
    def test_a_pitch_sets_the_rate_the_filter_and_the_timer(self):
        model, _ = run(('init',), ('load', 0, 'tone'), ('pitch', 0, sp.bits(2.0)))
        b = model.buffers[0]
        self.assertEqual((b['rate'], sp.reduced(48000, b['rate']), b['coef'], b['t_int'], b['t_frac']), (24000, (2, 1), sp.f32(math.exp(-math.pi / 2)), 1, 0))
        for pitch, rate in ((0.5, 96000), (1.5, 32000), (1.0001, 47995), (0.9999999, 48000), (1e9, 48000)):    # a rate of 0 is refused: the last one stays
            model.step(('pitch', 0, sp.bits(pitch)))
            self.assertEqual(b['rate'], rate, pitch)
        b.update(rate=96000, t_frac=1)
        sp.set_rate(b, 32000)          # half an input frame at 1:2 is one and a half thirds at 3:2
        self.assertEqual((sp.reduced(48000, 32000), b['t_int'], b['t_frac']), ((3, 2), 1, 1))

    def test_a_pitched_buffer_reads_ahead_and_keeps_a_residual(self):
        model, _ = run(('init',), ('load', 0, 'tone'), ('pitch', 0, sp.bits(2.0)), ('play', 0))
        mixed = model.mix(3)
        b = model.buffers[0]
        self.assertEqual((len(mixed), b['cursor'], b['t_int'], len(b['residual']), model.undefined), (6, 6, 2, 1, False))   # 6 frames read for 3: 5 used
        self.assertNotEqual(b['r1'], [0.0, 0.0])
        self.assertEqual(len(model.mix(480)), 960)
        self.assertEqual((b['playing'], model.buffers[0]['playing'], model.buffers[0]['cursor']), (True, False, 0))
        model, _ = run(('init',), ('load', 0, 'tone'), ('pitch', 0, sp.bits(0.5)), ('play', 0))
        model.mix(7)
        self.assertEqual((model.buffers[0]['cursor'], len(model.buffers[0]['residual']), model.buffers[0]['t_frac']), (4, 0, 1))        # (float)48000/96000*7 = 3.5: 3 frames, then 1 more


class StreamTests(unittest.TestCase):
    def words(self, *values):
        return [sp.bits(v) for v in values]

    def test_a_stream_is_two_zeroed_halves_in_its_own_format(self):
        model, _ = run(('init',), ('stream', 0, 44100, 16, 1), ('default', 100), ('stream', 1, 22050, 8, 2), ('default', 600), ('stream', 2, 48000, 32, 3))
        self.assertEqual(model.sounds[:3], [(1, 0, 44100, 16, 1), (2, 0, 22050, 8, 2), (3, 0, 48000, 32, 3)])
        self.assertEqual([(b['frames'], len(model.blocks[b['id']]), b['source'], len(b['x0']), b['coef'] is None) for b in model.buffers],
                         [(25600, 25600, 44100, 1, False), (960, 1920, 22050, 2, False), (1200, 3600, 48000, 2, True)])
        self.assertEqual((model.buffers[0]['stream'], model.undefined), (dict(size=16, channels=1, first=True, second=True), False))
        self.assertTrue(model.state().endswith(',0,2166136261,32/3/11'))

    def test_no_buffer_where_raylib_makes_none_and_where_jonlib_refuses(self):
        model, _ = run(('stream', 0, 44100, 16, 1), ('init',), ('stream', 1, 0, 16, 1), ('stream', 2, 44100, 16, 0))
        self.assertEqual((model.sounds[:3], model.buffers, model.undefined), ([(0, 0, 44100, 16, 1), (0, 0, 0, 16, 1), (0, 0, 44100, 16, 0)], [], False))
        for steps in ((('stream', 0, 44100, 24, 1),), (('default', 0xFFFFFFFF), ('stream', 0, 44100, 16, 1)), (('default', 3000000), ('stream', 0, 44100, 16, 1))):
            model, _ = run(('init',), *steps)
            self.assertEqual((model.buffers, model.undefined), ([], True), steps)

    def test_an_update_fills_the_first_processed_half(self):
        model, _ = run(('default', 480), ('init',), ('stream', 0, 44100, 16, 2), ('feed', 0, 2, [1, 2, 3, 4]))
        b = model.buffers[0]
        self.assertEqual((model.blocks[1][:6], b['stream']['first'], b['stream']['second']), ([1, 2, 3, 4, 0, 0], False, True))
        model.step(('feed', 0, 480, [7] * 960))
        self.assertEqual((model.blocks[1][958:962], b['stream']['first'], b['stream']['second']), ([0, 0, 7, 7], False, False))
        model.step(('feed', 0, 1, [9, 9]))                    # no half is processed: nothing
        self.assertEqual((model.blocks[1][:2], model.undefined), ([1, 2], False))
        model.step(('play', 0))                               # both are again
        model.step(('feed', 0, 481, []))                      # too many frames: nothing is written
        self.assertEqual((b['stream'], model.blocks[1][:2], model.undefined), (dict(size=16, channels=2, first=True, second=True), [1, 2], False))
        model.step(('feed', 0, 1, [5]))                       # a list that is not frames*channels long
        self.assertEqual((model.blocks[1][:2], model.undefined), ([1, 2], True))

    def test_a_stream_resamples_from_its_own_rate(self):
        model, _ = run(('init',), ('default', 480), ('stream', 0, 44100, 16, 1), ('pitch', 0, sp.bits(2.0)))
        b = model.buffers[0]
        self.assertEqual((b['source'], b['rate'], sp.reduced(b['source'], b['rate']), b['coef']), (44100, 24000, (147, 80), sp.f32(math.exp(-math.pi * 80 / 147))))
        model.step(('play', 0))
        model.step(('mix', 2))                                # nothing was fed: zeros, and the cursor stays
        b = model.buffers[0]
        self.assertEqual((model.mixed, model.undefined, b['cursor'], b['t_int'], b['t_frac'], b['residual'], b['playing']), ([0, 0, 0, 0], False, 0, 2, 54, [[0]], True))

    def test_a_playing_stream_reads_its_halves_and_marks_them_processed(self):
        data = [sp.bits(v) for v in (0.5, -0.5, 0.25, -0.25, 0.125, -0.125, 1.0, -1.0)] + [0] * 952
        model, _ = run(('default', 480), ('init',), ('stream', 0, 48000, 32, 2), ('play', 0), ('feed', 0, 480, data))
        self.assertEqual(model.mix(3), self.words(0.0, 0.0, 0.34375, -0.34375, 0.171875, -0.171875))      # one frame late, at the center's 0.6875
        b = model.buffers[0]
        self.assertEqual((b['frames'], b['cursor'], b['stream']['first'], b['stream']['second'], b['playing']), (960, 3, False, True, True))
        self.assertEqual(model.mix(480)[:4], self.words(0.0859375, -0.0859375, 0.6875, -0.6875))
        b = model.buffers[0]                                  # the fed half is read through; the other was not fed: zeros, and the cursor waits
        self.assertEqual((b['cursor'], b['stream']['first'], b['stream']['second'], b['playing'], model.undefined), (480, True, True, True, False))
        model.step(('feed', 0, 480, data))                    # the first processed half takes it: the one the cursor is not in
        model.mix(1)
        b = model.buffers[0]
        self.assertEqual((model.blocks[b['block']][:2], b['cursor'], b['stream']['first'], b['stream']['second']), (data[:2], 1, False, True))

    def test_a_mono_stream_sounds_on_both_sides(self):
        model, _ = run(('default', 480), ('init',), ('stream', 0, 48000, 16, 1), ('play', 0), ('feed', 0, 480, [16384, 0xC000, 8192] + [0] * 477))
        self.assertEqual(model.mix(4), self.words(0.0, 0.0, 0.34375, 0.34375, -0.34375, -0.34375, 0.171875, 0.171875))

    def test_the_frames_read_at_once_are_those_4096_bytes_hold(self):
        for size, channels, cursor, residual in ((16, 1, 3525, 4), (32, 2, 3527, 6), (8, 1, 3528, 7)):      # 2048, 512 and 4096 frames of the 3528 wanted
            model, _ = run(('default', 4800), ('init',), ('stream', 0, 44100, size, channels), ('pitch', 0, sp.bits(8.0)), ('play', 0),
                           ('feed', 0, 4800, [0] * 4800 * channels), ('feed', 0, 4800, [0] * 4800 * channels), ('mix', 480))
            b = model.buffers[0]
            self.assertEqual((b['rate'], b['cursor'], len(b['residual']), model.undefined), (6000, cursor, residual, False), (size, channels))


class SoundCasesTests(unittest.TestCase):
    def test_every_case_is_named_for_whether_raylib_runs_it(self):
        items = sp.cases()
        ids = [item['id'] for item in items]
        self.assertEqual(len(ids), len(set(ids)))
        rows = [sp.expected(item, catalog()) for item in items]
        self.assertEqual([item['id'] for item, row in zip(items, rows) if item['id'].startswith('refused-') == row[2]], [])
        self.assertEqual((len(items), sum(row[2] for row in rows), sum(len(item['steps']) for item in items)), (94, 65, 905))
        for tagged, plain, _ in rows:
            self.assertEqual(';'.join(part.split(' ', 1)[1] for part in tagged.split(';')), plain)
        used = {step[2] for item in items for step in item['steps'] if step[0] == 'load'}
        self.assertEqual(used, set(sp.waves()))
        self.assertEqual({step[2] for item in items for step in item['steps'] if step[0] == 'file'}, set(sp.FILES) | set(sp.FILE_ERRORS) | {'tiny'})

    def test_the_reference_script_and_the_bend_steps(self):
        table = sp.waves()
        order = ['boom', 'tiny']
        blob = sp.script([(False, [('init',), ('load', 2, 'mono16'), ('file', 1, 'tiny'), ('pan', 3, 5), ('update', 0, 1, [8, 9])])], table, order)
        words = list(struct.unpack('<%dI' % (len(blob) // 4), blob))
        self.assertEqual(words[:8], [1, 5, 0, 0, 0, 0, 0, 0])
        self.assertEqual(words[8:23], [3, 2, 8, 48000, 10, 16, 1, 100, 65336, 300, 65136, 500, 64936, 700, 64736])
        self.assertEqual(words[23:], [4, 1, 1, 0, 0, 9, 3, 6, 5, 0, 10, 0, 1, 0, 2, 8, 9])
        paths = {'tiny': Path('/work/tiny.wav')}
        self.assertEqual([sp.bend_step(step, table, paths) for step in (('close',), ('master', 7), ('load', 1, 'one'), ('file', 2, 'tiny'), ('alias', 1, 0), ('unalias', 3),
                                                                        ('resume', 2), ('pitch', 0, 9), ('update', 1, 1, [4, 5]))],
                         ['OpClose{}', 'OpMaster{7}', 'OpLoad{1, 1, 44100, 16, 1, [12345]}', 'OpFile{2, "/work/tiny.wav"}', 'OpAlias{1, 0}', 'OpUnalias{3}', 'OpAct{2, 3}',
                          'OpTune{0, 5, 9}', 'OpUpdate{1, 1, [4, 5]}'])
        keys, steps = sp.catalog_steps(table, order)
        self.assertEqual((len(keys), len(steps), keys[-2:], steps[:4]),
                         (20, 61, [('file', 'boom'), ('file', 'tiny')], [('init',), ('load', 0, 'mono16'), ('dump', 0), ('unload', 0)]))

    def test_the_small_wav_file(self):
        data = sp.tiny_wav()
        self.assertEqual((data[:4], struct.unpack_from('<I', data, 4)[0] + 8, data[8:16]), (b'RIFF', len(data), b'WAVEfmt '))
        self.assertEqual(struct.unpack_from('<IHHIIHH', data, 16), (16, 1, 1, 11025, 11025, 1, 8))
        self.assertEqual((data[36:40], struct.unpack_from('<I', data, 40)[0], len(data)), (b'data', 10, 54))


if __name__ == '__main__':
    unittest.main()
