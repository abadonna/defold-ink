"""Run with Python + lupa (pip install lupa), from any directory.

Uses LuaJIT 2.1, as Defold does. JSON decoding and pprint are the only host shims.
The adjacent .json fixture is compiled from sequence.ink with inkjs 2.4.0.
"""
import json
from pathlib import Path
import unittest

from lupa.luajit21 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class SequenceTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("package.path = ... .. '/?.lua;' .. package.path", ROOT.as_posix())
        self.lua.execute("bit = require 'bit'; pprint = function(...) error(tostring(select(2, ...)), 0) end")
        self.null = self.lua.eval("newproxy()")
        self.lua.globals().decode_json = self.decode
        self.lua.execute("json = {decode = function(s) return decode_json(s) end}")
        self.create = self.lua.eval("require('ink.story').create")
        self.source = (ROOT / 'tests/sequence.json').read_text(encoding='utf-8-sig')
        self.story = self.create(self.source)
        self.lua.execute('math.randomseed(37)')

    def decode(self, source, *_):
        def convert(value):
            if value is None:
                return self.null
            if isinstance(value, dict):
                return self.lua.table_from({k: convert(v) for k, v in value.items()})
            if isinstance(value, list):
                return self.lua.table_from([convert(v) for v in value])
            return value
        return convert(json.loads(source))

    def jump(self, name='shuffle_cycle', story=None):
        paragraphs, choices = (story or self.story).jump(name)
        self.assertEqual(len(choices), 0)
        return tuple(paragraphs[i].text for i in range(1, len(paragraphs) + 1))

    def test_every_cycle_is_a_permutation(self):
        for _ in range(20):
            self.assertEqual({self.jump()[0] for _ in range(3)}, {'One', 'Two', 'Three'})

    def test_sequences_are_independent(self):
        first, second = set(), set()
        for _ in range(3):
            first.add(self.jump()[0])
            second.add(self.jump('other_cycle')[0])
        self.assertEqual(first, {'One', 'Two', 'Three'})
        self.assertEqual(second, {'Red', 'Green', 'Blue'})

    def test_shuffle_once_exhausts(self):
        self.assertEqual({self.jump('shuffle_once')[0] for _ in range(3)}, {'One', 'Two', 'Three'})
        for _ in range(3):
            self.assertEqual(self.jump('shuffle_once'), ())

    def test_shuffle_stopping_keeps_last(self):
        self.assertEqual({self.jump('shuffle_stopping')[0] for _ in range(2)}, {'One', 'Two'})
        for _ in range(4):
            self.assertEqual(self.jump('shuffle_stopping'), ('Last',))

    def test_single_element(self):
        for _ in range(5):
            self.assertEqual(self.jump('single'), ('Alone',))

    def test_tags_remain_attached_to_lines(self):
        for _ in range(6):
            paragraphs, _ = self.story.jump('shuffle_cycle')
            self.assertEqual(paragraphs[1].tags[1].strip(), 'variant:' + paragraphs[1].text.lower())

    def test_replay_restores_mid_cycle_and_returns_last_jump(self):
        self.jump()
        last = self.jump()
        saved = self.story.get_state()
        expected = self.jump()
        restored = self.create(self.source)
        paragraphs, _ = restored.restore(saved)
        self.assertEqual(tuple(paragraphs[i].text for i in range(1, len(paragraphs) + 1)), last)
        self.assertEqual(self.jump(story=restored), expected)

    def test_replay_uses_recorded_draws_without_calling_random(self):
        expected = []
        for name in ['shuffle_cycle', 'random_roll', 'other_cycle', 'shuffle_cycle', 'random_roll']:
            expected.append(self.jump(name))
        saved = self.story.get_state()
        restored = self.create(self.source)
        self.lua.execute("math.random = function() error('Unexpected random draw during replay') end")
        paragraphs, choices = restored.restore(saved)
        self.assertEqual(len(choices), 0)
        self.assertEqual((paragraphs[1].text,), expected[-1])
        self.assertEqual(len(restored.get_state().randoms), len(saved.randoms))
        self.assertEqual(len(restored.get_state().input), len(saved.input))

    def test_repeated_save_restore_preserves_unfinished_cycle(self):
        first = self.jump()[0]
        restored = self.create(self.source)
        restored.restore(self.story.get_state())
        second = self.jump(story=restored)[0]
        again = self.create(self.source)
        again.restore(restored.get_state())
        third = self.jump(story=again)[0]
        self.assertEqual({first, second, third}, {'One', 'Two', 'Three'})

    def test_legacy_serialization_without_shuffle_field_loads(self):
        saved = self.story.serialize()
        saved.shuffles = None
        restored = self.create(self.source)
        paragraphs, _ = restored.deserialize(saved, 'shuffle_cycle')
        self.assertIn(paragraphs[1].text, {'One', 'Two', 'Three'})

    def test_serialization_preserves_unfinished_permutation(self):
        self.jump()
        saved = self.story.serialize()
        expected = [self.jump(), self.jump()]
        restored = self.create(self.source)
        paragraphs, _ = restored.deserialize(saved, 'shuffle_cycle')
        self.assertEqual((paragraphs[1].text,), expected[0])
        self.assertEqual(self.jump(story=restored), expected[1])

    def test_seq_consumes_both_arguments(self):
        self.lua.execute('''
            local context = {__randoms = {}}
            local container = require('ink.container').create({'ev', 0, 3, 'seq', '/ev', 'done', {}})
            local stack = {}
            local output = {text = {}, tags = {}, paragraphs = {}, choices = {}}
            require('ink.process').create(context).run(container, output, nil, stack)
            assert(#stack == 1, 'seq must consume visit index and element count')
            assert(stack[1] >= 0 and stack[1] < 3)
        ''')


if __name__ == '__main__':
    unittest.main()
