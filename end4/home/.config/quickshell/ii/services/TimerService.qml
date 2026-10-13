pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Simple Pomodoro time manager.
 */
Singleton {
    id: root

    property int focusTime: Config.options.time.pomodoro.focus
    property int breakTime: Config.options.time.pomodoro.breakTime
    property int longBreakTime: Config.options.time.pomodoro.longBreak
    property int cyclesBeforeLongBreak: Config.options.time.pomodoro.cyclesBeforeLongBreak

    property bool pomodoroRunning: Persistent.states.timer.pomodoro.running
    property bool pomodoroBreak: Persistent.states.timer.pomodoro.isBreak
    property bool pomodoroLongBreak: Persistent.states.timer.pomodoro.isBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak);
    property int pomodoroLapDuration: pomodoroLongBreak ? longBreakTime : pomodoroBreak ? breakTime : focusTime // This is a binding that's to be kept
    property int pomodoroSecondsLeft: pomodoroLapDuration // Reasonable init value, to be changed
    property int pomodoroCycle: Persistent.states.timer.pomodoro.cycle

    property bool stopwatchRunning: Persistent.states.timer.stopwatch.running
    property int stopwatchTime: 0
    property int stopwatchStart: Persistent.states.timer.stopwatch.start
    property var stopwatchLaps: Persistent.states.timer.stopwatch.laps

    function applySettings(focusMinutes, breakMinutes, longBreakMinutes, cycles, autoBreak, autoFocus, notifications, sound) {
        const p = Config.options.time.pomodoro;
        const durationChanged = p.focus !== focusMinutes * 60 || p.breakTime !== breakMinutes * 60
            || p.longBreak !== longBreakMinutes * 60 || p.cyclesBeforeLongBreak !== cycles;
        p.focus = Math.max(1, Math.min(180, Math.round(focusMinutes))) * 60;
        p.breakTime = Math.max(1, Math.min(60, Math.round(breakMinutes))) * 60;
        p.longBreak = Math.max(1, Math.min(120, Math.round(longBreakMinutes))) * 60;
        p.cyclesBeforeLongBreak = Math.max(1, Math.min(12, Math.round(cycles)));
        p.autoStartBreak = autoBreak;
        p.autoStartFocus = autoFocus;
        p.notifications = notifications;
        Config.options.sounds.pomodoro = sound;
        if (durationChanged) resetPomodoro();
    }

    // General
    Component.onCompleted: {
        if (!stopwatchRunning)
            stopwatchReset();
    }

    function getCurrentTimeInSeconds() {  // Pomodoro uses Seconds
        return Math.floor(Date.now() / 1000);
    }

    function getCurrentTimeIn10ms() {  // Stopwatch uses 10ms
        return Math.floor(Date.now() / 10);
    }

    // Pomodoro
    function refreshPomodoro() {
        const now = getCurrentTimeInSeconds();
        if (now >= Persistent.states.timer.pomodoro.start + pomodoroLapDuration) {
            const nextBreak = !pomodoroBreak;
            if (!nextBreak) {
                Persistent.states.timer.pomodoro.cycle = (pomodoroCycle + 1) % Math.max(1, cyclesBeforeLongBreak);
            }
            Persistent.states.timer.pomodoro.isBreak = nextBreak;
            Persistent.states.timer.pomodoro.start = now;
            const duration = nextBreak
                ? (pomodoroCycle + 1 === cyclesBeforeLongBreak ? longBreakTime : breakTime)
                : focusTime;
            let message = nextBreak
                ? (pomodoroCycle + 1 === cyclesBeforeLongBreak
                    ? Translation.tr("Long break: %1 minutes")
                    : Translation.tr("Break: %1 minutes"))
                : Translation.tr("Focus: %1 minutes");
            if (Config.options.time.pomodoro.notifications)
                Quickshell.execDetached(["notify-send", "Pomodoro", message.arg(Math.floor(duration / 60)), "-a", "Shell"]);
            if (Config.options.sounds.pomodoro) Audio.playSystemSound("alarm-clock-elapsed");
            pomodoroSecondsLeft = duration;
            Persistent.states.timer.pomodoro.running = nextBreak
                ? Config.options.time.pomodoro.autoStartBreak
                : Config.options.time.pomodoro.autoStartFocus;
            return;
        }
        pomodoroSecondsLeft = Math.max(0, pomodoroLapDuration - (now - Persistent.states.timer.pomodoro.start));
    }

    Timer {
        id: pomodoroTimer
        interval: 200
        running: root.pomodoroRunning
        repeat: true
        onTriggered: refreshPomodoro()
    }

    function togglePomodoro() {
        Persistent.states.timer.pomodoro.running = !pomodoroRunning;
        if (Persistent.states.timer.pomodoro.running) {
            // Start/Resume
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds() + pomodoroSecondsLeft - pomodoroLapDuration;
        }
    }

    function resetPomodoro() {
        Persistent.states.timer.pomodoro.running = false;
        Persistent.states.timer.pomodoro.isBreak = false;
        Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();
        Persistent.states.timer.pomodoro.cycle = 0;
        pomodoroSecondsLeft = focusTime;
    }

    // Stopwatch
    function refreshStopwatch() {  // Stopwatch stores time in 10ms
        stopwatchTime = getCurrentTimeIn10ms() - stopwatchStart;
    }

    Timer {
        id: stopwatchTimer
        interval: 10
        running: root.stopwatchRunning
        repeat: true
        onTriggered: refreshStopwatch()
    }

    function toggleStopwatch() {
        if (root.stopwatchRunning)
            stopwatchPause();
        else
            stopwatchResume();
    }

    function stopwatchPause() {
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchResume() {
        if (stopwatchTime === 0) Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = true;
        Persistent.states.timer.stopwatch.start = getCurrentTimeIn10ms() - stopwatchTime;
    }

    function stopwatchReset() {
        stopwatchTime = 0;
        Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchRecordLap() {
        Persistent.states.timer.stopwatch.laps.push(stopwatchTime);
    }
}
