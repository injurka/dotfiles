import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('power_saving', Path(__file__).with_name('controller.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
REAL_SET_VALUE = m.set_value


class PowerSavingTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.values = {('profile', ''): 'balanced', ('brightness', 'panel'): 80,
                       ('option', 'animations:enabled'): True,
                       ('option', 'decoration:blur:enabled'): True,
                       ('monitor', 'eDP-1'): '1920x1080@144.000'}
        patches = [patch.object(m, 'CONFIG', Path(self.tmp.name) / 'config.json'),
                   patch.object(m, 'STATE', Path(self.tmp.name) / 'state.json'),
                   patch.object(m, 'SESSION', 'test-session'),
                   patch.object(m, 'battery', return_value=(True, False)),
                   patch.object(m, 'backlight', return_value='panel'),
                   patch.object(m, 'run', return_value='100'),
                   patch.object(m, 'get_value', side_effect=lambda k, t: self.values[k, t]),
                   patch.object(m, 'set_value', side_effect=self.set_value),
                   patch.object(m, 'monitors', return_value=[dict(name='eDP-1', width=1920, height=1080,
                       refreshRate=144, availableModes=['1920x1080@60.00Hz', '1280x720@60.00Hz']),
                       dict(name='DP-1', width=3840, height=2160, refreshRate=240,
                       availableModes=['3840x2160@60.00Hz'])])]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def set_value(self, kind, target, value):
        self.values[kind, target] = value

    def test_enable_restore_after_shell_restart(self):
        before = self.values.copy()
        c = m.Controller()
        c.config['refresh'] = True
        c.enable()
        self.assertEqual(self.values['brightness', 'panel'], 35)
        self.assertEqual(self.values['monitor', 'eDP-1'], '1920x1080@60.000')
        self.assertEqual(len(c.state['changes']), 5)
        m.Controller().disable()
        self.assertEqual(self.values, before)
        self.assertFalse(m.Controller().state['active'])

    def test_manual_changes_win(self):
        c = m.Controller()
        c.enable()
        self.values['brightness', 'panel'] = 50
        c.disable()
        self.assertEqual(self.values['brightness', 'panel'], 50)

    def test_never_raise_brightness(self):
        self.values['brightness', 'panel'] = 15
        c = m.Controller()
        c.enable()
        self.assertEqual(self.values['brightness', 'panel'], 15)
        self.assertFalse(any(x['kind'] == 'brightness' for x in c.state['changes']))

    def test_partial_failure_and_retry_restore(self):
        c = m.Controller()
        c.enable()
        with patch.object(m, 'set_value', side_effect=RuntimeError('temporarily unavailable')):
            c.disable()
        self.assertTrue(c.state['active'])
        self.assertTrue(c.state['errors'])
        c.disable()
        self.assertFalse(c.state['active'])
        self.assertEqual(self.values['profile', ''], 'balanced')

    def test_failed_apply_is_not_marked_active(self):
        c = m.Controller()
        with patch.object(m, 'set_value', side_effect=RuntimeError('permission denied')):
            c.enable()
        self.assertFalse(c.state['active'])
        self.assertEqual(c.state['changes'], [])
        self.assertTrue(c.state['errors'])

    def test_new_session_does_not_restore_old_settings(self):
        c = m.Controller()
        c.enable()
        with patch.object(m, 'SESSION', 'new-session'):
            fresh = m.Controller()
            self.assertFalse(fresh.state['active'])
            fresh.disable()
        self.assertEqual(self.values['profile', ''], 'power-saver')

    def test_automation_only_on_transitions(self):
        c = m.Controller()
        c.config.update(autoBattery=True, restoreAC=True)
        c.tick()
        self.assertFalse(c.state['active'])
        with patch.object(m, 'battery', return_value=(True, True)):
            c.tick()
        c.tick()
        self.assertTrue(c.state['active'])
        c.disable()  # User override until next plug/unplug.
        c.tick()
        self.assertFalse(c.state['active'])
        with patch.object(m, 'battery', return_value=(True, True)):
            c.tick()
        c.tick()
        self.assertTrue(c.state['active'])
        with patch.object(m, 'battery', return_value=(True, True)):
            c.tick()
        self.assertFalse(c.state['active'])

    def test_unsupported_refresh_keeps_resolution(self):
        c = m.Controller()
        c.config.update(refresh=True, hz=30)
        c.enable()
        self.assertEqual(self.values['monitor', 'eDP-1'], '1920x1080@144.000')
        self.assertTrue(any('refresh rate' in error for error in c.state['errors']))

    def test_lua_commands_preserve_panel_geometry(self):
        panel = dict(name='eDP-1', x=100, y=200, scale=1.5, transform=1,
                     currentFormat='XRGB2101010')
        with patch.object(m, 'run', return_value='ok') as command:
            REAL_SET_VALUE('option', 'decoration:blur:enabled', False)
            self.assertEqual(command.call_args.args,
                ('hyprctl', 'eval', 'hl.config({decoration={blur={enabled=false}}})'))
            with patch.object(m, 'monitors', return_value=[panel]):
                REAL_SET_VALUE('monitor', 'eDP-1', '1920x1080@60.000')
            lua = command.call_args.args[2]
            self.assertIn('position="100x200"', lua)
            self.assertIn('scale=1.5', lua)
            self.assertIn('transform=1', lua)
            self.assertIn('bitdepth=10', lua)

    def test_asynchronous_modeset_waits(self):
        with patch.object(m, 'get_value', side_effect=['1920x1080@144.000', '1920x1080@60.001']), \
                patch.object(m.time, 'sleep') as sleep:
            self.assertEqual(m.verify('monitor', 'eDP-1', '1920x1080@60.000'), '1920x1080@60.001')
            sleep.assert_called_once()

    def test_desktop_enable_does_nothing(self):
        with patch.object(m, 'battery', return_value=(False, True)):
            c = m.Controller()
            with self.assertRaises(RuntimeError):
                c.enable()
        self.assertFalse(c.state['active'])


if __name__ == '__main__':
    unittest.main()
