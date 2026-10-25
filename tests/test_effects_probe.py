import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import effects_probe as probe
import examples_probe as ep

ROOT = Path(__file__).resolve().parents[1]


class EffectsProbeTests(unittest.TestCase):
    def test_the_reference_loop_does_io_before_begin_drawing_and_after_end_drawing(self):
        source = (ROOT / 'tools/reference/driver_effects.c').read_text()
        order = ['InitWindow(160, 90', 'IsKeyPressed(KEY_S)', 'SaveFileText("effects.txt"', 'IsKeyPressed(KEY_L)', 'LoadFileText("effects.txt")', 'BeginDrawing();',
                 'EndDrawing();', 'IsKeyDown(KEY_F)', 'counter + 1000']
        places = [source.index(step) for step in order]
        self.assertEqual(places, sorted(places))

    def test_the_bend_module_is_an_effects_program_with_the_same_steps(self):
        module = (ROOT / 'tools/reference/driver_effects.bend').read_text()
        for call in ('J.Effects{', 'J.Files.save_text(file(state), U32.show(counter.of(state)))', 'J.Files.load_text(file(state))', 'J.Input.is_key_down(core, 70)',
                     '(counter.of(state) + 1000 : U32)', 'J.Input.is_key_pressed(core, 83)', 'J.Input.is_key_pressed(core, 76)'):
            self.assertIn(call, module)

    def test_the_scripts_read_a_missing_file_first_and_every_write_back(self):
        missing, files = probe.scripts()
        self.assertEqual(missing['name'], 'driver_effects-missing')
        keys = lambda item: [[(event[1], event[0]) for event in frame['events']] for frame in item['frames']]
        self.assertFalse(any(code in (probe.KEY_S, probe.KEY_F) for frame in keys(missing) for code, _ in frame))
        pressed = [code for frame in keys(files) for code, _ in frame]
        self.assertLess(pressed.index(probe.KEY_S), pressed.index(probe.KEY_L))
        self.assertLess(pressed.index(probe.KEY_F), len(pressed) - 1 - pressed[::-1].index(probe.KEY_L))
        self.assertEqual(len(files['frames']), 8)

    def test_registering_makes_it_an_effects_program_of_the_examples_probe(self):
        probe.register()
        try:
            self.assertIn(probe.NAME, ep.EFFECTS)
            self.assertIn(probe.NAME, ep.IO_SETUP)
            self.assertIn(probe.NAME, ep.SCRATCH)
            self.assertEqual(ep.size_of(probe.NAME), (160, 90))
            text = ep.render(probe.scripts(), 'Glibc239Libm', None, Path('/raylib'), {0: Path('/tmp/x0'), 1: Path('/tmp/x1')})([probe.NAME], False)
            self.assertIn('import ../../tools/reference/driver_effects.bend as Ex', text)
            self.assertIn('J.Program.replay_io(~Ex.State, ~Ex.program(M.Glibc239Libm{})', text)
            self.assertIn('def replay(+dir: String, script: +List<J.ReplayFrame>', text)
            self.assertIn('Ex.setup(dir, core, frame)', text)
            self.assertIn('replay("/tmp/x0/", script.n0(), J.Core.init_window_flags(0, 160, 90', text)
            self.assertIn('replay("/tmp/x1/", script.n1(), ', text)
        finally:
            for table in (ep.EXAMPLES, ep.MODULES, ep.SIZES):
                table.pop(probe.NAME, None)
            for names in (ep.IO_SETUP, ep.EFFECTS, ep.SCRATCH):
                names.discard(probe.NAME)

    def test_an_example_keeps_its_module_and_the_pure_replay(self):
        text = ep.render([item for item in ep.scripts() if item['example'] == 'core_basic_window'], 'Glibc239Libm', None, Path('/raylib'))(['core_basic_window'], False)
        self.assertIn('import ../../examples/core_basic_window.bend as Ex', text)
        self.assertIn('join(J.Program.replay(~Ex.State', text)
        self.assertNotIn('replay_io', text)
        shadow = ep.render([item for item in ep.scripts() if item['example'] == 'shaders_shadowmap_rendering'], 'Glibc239Libm', None, Path('/raylib'))(
            ['shaders_shadowmap_rendering'], False)
        self.assertIn('J.Program.replay_io(~Ex.State', shadow)


class ScratchScriptTests(unittest.TestCase):
    """The examples that write files (tools/examples_probe.py's SCRATCH)."""

    def items(self):
        return [item for item in ep.scripts() if item['example'] == 'core_storage_values']

    def test_a_script_gets_its_directory_after_its_seed(self):
        items = self.items()
        text = ep.render(items, 'Glibc239Libm', None, Path('/raylib'), {index: Path(f'/tmp/s{index}') for index in range(len(items))})(['core_storage_values'], False)
        self.assertIn('def replay(+seed: U32, +dir: String, script: +List<J.ReplayFrame>', text)
        self.assertIn('Ex.setup(seed, dir, core, frame)', text)
        self.assertIn(f'replay({items[0]["seed"]}, "/tmp/s0/", script.n0(), ', text)
        self.assertIn('J.Program.replay_io(~Ex.State', text)

    def test_the_undefined_scripts_start_from_files_and_name_their_frame(self):
        names = {item['name']: item for item in self.items()}
        self.assertEqual(set(ep.UNDEFINED_FROM) & set(names), {'core_storage_values-short', 'core_storage_values-odd'})
        for name, cut in ep.UNDEFINED_FROM.items():
            if name in names:
                self.assertIn(name, ep.FILES)
                self.assertLess(cut, len(names[name]['frames']))
                self.assertEqual(ep.refusal(names[name], 'Glibc239Libm'), cut)
                self.assertEqual(ep.refusal(names[name], 'AppleLibm'), cut)
        self.assertEqual(len(ep.FILES['core_storage_values-short']['storage.data']), 4)
        self.assertEqual(len(ep.FILES['core_storage_values-odd']['storage.data']) % 4, 2)
        self.assertEqual(len(ep.FILES['core_storage_values-longer']['storage.data']), 12)
        self.assertIsNone(ep.refusal(names['core_storage_values-values'], 'Glibc239Libm'))

    def test_a_recording_cannot_be_stopped_by_the_probes_input(self):
        """raylib ignores PlayAutomationEvent while it records, so the record script only starts one."""
        record = next(item for item in ep.scripts() if item['name'] == 'core_automation_events-record')
        keys = [(code, kind) for frame in record['frames'] for kind, code, _, _ in frame['events']]
        self.assertEqual(keys[0], (83, ep.KEY_DOWN_EVENT))
        self.assertGreaterEqual(len(record['frames']), 2 + 15)
        self.assertIn('core_automation_events', ep.SCRATCH)
        self.assertIn('core_automation_events', ep.EFFECTS)
        self.assertNotIn('core_automation_events-record', ep.UNDEFINED_FROM)

    def test_the_directories_are_emptied_and_given_their_files(self):
        import tempfile

        class Probe:
            pass

        with tempfile.TemporaryDirectory() as work:
            probe = Probe()
            probe.work = Path(work)
            items = self.items()
            short = next(index for index, item in enumerate(items) if item['name'] == 'core_storage_values-short')
            for native in (False, True):
                ep.scratch_reset(probe, items, native=native)
                self.assertEqual(ep.scratch_left(probe, 0, native), {})
                self.assertEqual(ep.scratch_left(probe, short, native), ep.FILES['core_storage_values-short'])
                (ep.scratch(probe, 0, native) / 'storage.data').write_bytes(b'abcd')
                self.assertEqual(ep.scratch_left(probe, 0, native), {'storage.data': b'abcd'})
                ep.scratch_reset(probe, items, 'core_storage_values', native)
                self.assertEqual(ep.scratch_left(probe, 0, native), {})
            self.assertNotEqual(ep.scratch(probe, 0), ep.scratch(probe, 0, native=True))


class ClockExampleTests(unittest.TestCase):
    """The examples that read the C library's time()."""

    def test_the_shim_redirects_time_in_the_examples_translation_unit(self):
        shim = ep.SHIM.read_text()
        for line in ('#include <time.h>', 'time_t JonlibExampleTime(time_t *out);', '#define time(x) JonlibExampleTime(x)', '#define localtime(x) gmtime(x)'):
            self.assertIn(line, shim)
        self.assertLess(shim.index('#include <time.h>'), shim.index('#define time(x)'))
        self.assertIn('time_t JonlibExampleTime(time_t *out) { time_t now = (time_t)seed + (time_t)probe_clock;', ep.C_DRIVER)

    def test_the_clock_script_crosses_a_second_and_the_hour(self):
        item = next(item for item in ep.scripts() if item['example'] == 'shapes_digital_clock')
        self.assertIn('shapes_digital_clock', ep.SEEDED)
        times = [item['seed'] + int(item['start'])] + [item['seed'] + int(frame['after']) for frame in item['frames'][:-1]]
        self.assertEqual(times[0], 13 * 3600 + 59 * 60 + 58)
        self.assertIn(14 * 3600, times)
        self.assertEqual(sorted(set(times)), [50398, 50399, 50400, 50401])
        self.assertEqual(ep.refusal(item, 'Glibc239Libm'), None)
        self.assertEqual(ep.refusal(item, 'AppleLibm'), 'reported')


    def test_the_clock_of_clocks_table_is_the_examples(self):
        import re
        port = (ROOT / 'examples/shapes_clock_of_clocks.bend').read_text()
        rows = re.findall(r'    case (\d|_): \[([0-9, ]+)\]', port)
        self.assertEqual([name for name, _ in rows], [str(d) for d in range(9)] + ['_'])
        table = [[int(v) for v in body.split(', ')] for _, body in rows]
        self.assertTrue(all(len(row) == 24 and max(row) <= 6 for row in table))
        # Every digit ends its last row at the bottom corners, and only 1, 4 and 7 leave cells unused (ZZ, 6).
        self.assertEqual({tuple(row[-2:]) for row in table}, {(4, 2), (3, 2)})
        self.assertEqual([d for d, row in enumerate(table) if 6 in row], [1, 4, 7])
        for symbol, angles in enumerate(('0.0, 90.0', '90.0, 180.0', '180.0, 270.0', '0.0, 270.0', '0.0, 180.0', '90.0, 270.0')):
            self.assertIn(f'    case {symbol}: M.Vector2{{{angles}}}', port)
        self.assertIn('    case _: M.Vector2{135.0, 135.0}', port)

    def test_the_clock_of_clocks_script_ticks_in_both_hour_modes(self):
        item = next(item for item in ep.scripts() if item['example'] == 'shapes_clock_of_clocks')
        self.assertIn('shapes_clock_of_clocks', ep.SEEDED)
        times = [item['seed'] + int(item['start'])] + [item['seed'] + int(frame['after']) for frame in item['frames'][:-1]]
        self.assertEqual(sorted(set(times)), [50398, 50399])
        space = next(k for k, frame in enumerate(item['frames']) if any(code == 32 and kind == ep.KEY_DOWN_EVENT for kind, code, _, _ in frame['events']))
        self.assertLess(space, times.index(50399))
        self.assertGreaterEqual(len(item['frames']) - times.index(50399), 6)
        self.assertEqual(ep.refusal(item, 'AppleLibm'), 'reported')


class OwnWaitExampleTests(unittest.TestCase):
    """core_custom_frame_control waits itself after EndDrawing."""

    def test_the_next_frame_starts_after_the_examples_wait(self):
        item = next(item for item in ep.scripts() if item['example'] == 'core_custom_frame_control')
        frames = item['frames']
        self.assertTrue(all(frame['after'] == frame['end'] for frame in frames))
        target = ep.fp.f32(1.0 / ep.fp.f32(60.0))
        measured, waits = item['start'], []
        for frame, following in zip(frames, frames[1:]):
            wait = target - (frame['after'] - measured)
            clock = frame['after'] + ep.fp.f32(wait) if wait > 0.0 else frame['after']
            waits.append(wait > 0.0)
            self.assertGreater(following['begin'], clock)
            self.assertLess(following['begin'] - clock, 0.0031)
            measured = clock
        self.assertIn(True, waits)
        self.assertIn(False, waits)

    def test_other_examples_keep_their_clocks(self):
        self.assertEqual(ep.own_wait('core_basic_window', 0.25, 0.5), 0.5)
        self.assertEqual(ep.own_wait('core_custom_frame_control', 0.25, 0.5), 0.5)
        self.assertGreater(ep.own_wait('core_custom_frame_control', 0.25, 0.255), 0.255)
        self.assertIn('#define WaitTime JonlibExampleWaitTime', ep.SHIM.read_text())
        self.assertIn('void JonlibExampleWaitTime(double seconds) { if (!(seconds < 0)) probe_after = probe_clock + seconds; WaitTime(seconds); }', ep.C_DRIVER)


class EmojiExampleTests(unittest.TestCase):
    def test_the_tables_have_the_examples_sizes(self):
        import re
        port = (ROOT / 'examples/text_unicode_emojis.bend').read_text()
        table = port[port.index('def emojis() -> +List<U32>:'):port.index('def message(index: U32)')]
        codes = [int(v) for v in re.findall(r'\b(\d{5,6})\b', table)]
        self.assertEqual(len(codes), 180)
        self.assertEqual(codes[0], 0x1F300)
        self.assertTrue(all(0x1F300 <= code <= 0x1F9FF for code in codes))
        cases = re.findall(r'    case (\d+|_): Message\{"((?:[^"\\]|\\.)*)", "([A-Za-z]+)"\}', port)
        self.assertEqual([name for name, _, _ in cases], [str(i) for i in range(46)] + ['_'])
        self.assertEqual(len({language for _, _, language in cases}), 11)
        self.assertIn('J.Random.value(rng, 0.0, (47.0 - 1.0 : F32))', port)

    def test_the_script_clicks_five_emoji_of_81_pixels(self):
        item = next(item for item in ep.scripts() if item['example'] == 'text_unicode_emojis')
        clicks = []
        position = None
        for frame in item['frames']:
            for kind, a, b, _ in frame['events']:
                if kind == ep.MOUSE_POSITION:
                    position = (a, b)
                elif kind == ep.MOUSE_DOWN:
                    clicks.append(position)
        def emoji(x, y):
            for i in range(32):
                row = 0 if i <= 8 else 1 + (i - 9) // 8
                column = i if i <= 8 else (i - 9) % 8
                left, top = 28.8 + 109.8 * column, 10 + 105.25 * row
                if left <= x < left + 81 and top <= y < top + 81:
                    return i
        self.assertEqual([emoji(*click) for click in clicks], [0, 6, 20, 31, 13])


class FileTimeExampleTests(unittest.TestCase):
    def test_the_header_answers_the_examples_file_time_with_the_seed(self):
        self.assertIn('#define GetFileModTime JonlibExampleFileModTime', ep.SHIM.read_text())
        self.assertIn('long JonlibExampleFileModTime(const char *fileName) { (void)fileName; return (long)seed; }', ep.C_DRIVER)
        self.assertIn('shaders_hot_reloading', ep.SEEDED)

    def test_the_scripts_stamps_are_a_thursday_and_a_leap_day(self):
        import time
        seeds = {item['name']: item['seed'] for item in ep.scripts() if item['example'] == 'shaders_hot_reloading'}
        self.assertEqual(time.asctime(time.gmtime(seeds['shaders_hot_reloading-stamp'])), 'Thu Oct  9 08:53:20 2025')
        self.assertEqual(time.asctime(time.gmtime(seeds['shaders_hot_reloading-leap'])), 'Thu Feb 29 23:59:59 2024')
        port = (ROOT / 'examples/shaders_hot_reloading.bend').read_text()
        self.assertIn('"%s %s%3d %02d:%02d:%02d %d\\n"', port)
        self.assertIn('(days + 719468 : U32)', port)


class UndefinedNativeExampleTests(unittest.TestCase):
    def test_the_codepoints_example_runs_on_6_2_and_only_its_step_before_the_text_is_undefined(self):
        import re
        text = (ROOT / 'examples/text_codepoints_loading.bend').read_text()
        literal = re.search(r'def text\(\) -> String:\n  "(.*)"', text).group(1)
        data = bytes(int(code, 16) for code in re.findall(r'\\u\{([0-9a-f]+)\}', literal.replace('\\n', '\\u{a}')))
        points = [ord(c) for c in data.decode('utf-8')]
        self.assertEqual((len(points), len(set(points))), (54, 49))
        self.assertEqual(sorted(c for c in set(points) if points.count(c) > 1), [0x0A, 0x3000])
        # raylib 6.2's CodepointRemoveDuplicates no longer reads past its array: the example runs natively.
        self.assertEqual(ep.UNDEFINED_NATIVE, {})
        self.assertIn('text_codepoints_loading', ep.IO_SETUP)
        items = {item['name']: item for item in ep.scripts() if item['example'] == 'text_codepoints_loading'}
        self.assertEqual(sorted(items), ['text_codepoints_loading-before', 'text_codepoints_loading-frames'])
        for libm in ('Glibc239Libm', 'AppleLibm'):
            self.assertIsNone(ep.refusal(items['text_codepoints_loading-frames'], libm))
            self.assertEqual(ep.refusal(items['text_codepoints_loading-before'], libm), 1)
        self.assertIn('DotGothic16-Regular.ttf", 36, deduped()', text)

    def test_the_mixed_processor_refuses_when_apple_powf_has_no_answer(self):
        item = next(item for item in ep.scripts() if item['name'] == 'audio_mixed_processor-powers')
        self.assertIsNone(ep.refusal(item, 'Glibc239Libm'))
        self.assertEqual(ep.refusal(item, 'AppleLibm'), 1)
        self.assertEqual(ep.processor_refusal(item), 1)

    def test_the_stream_callback_example_runs_on_the_audio_clock(self):
        self.assertIn('audio_stream_callback', ep.AUDIO_CLOCK)
        self.assertIn('audio_stream_callback', ep.IO_SETUP)
        port = (ROOT / 'examples/audio_stream_callback.bend').read_text()
        self.assertIn('lines(799n, 0, recent, f4)', port)
        self.assertNotIn('sin64', port)


if __name__ == '__main__':
    unittest.main()
