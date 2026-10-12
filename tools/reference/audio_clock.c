/*
 * Probe-only audio clock for tools/examples_probe.py; not part of raylib.
 *
 * raudio.c itself (the reference library has no audio module), compiled with
 * miniaudio's null backend only, plus two functions for the probe's driver.
 * raylib's device mixes on a thread of its own, when the host's time says
 * so: an example whose frames show what the device did (a stream's processed
 * halves, a sound that ended) is not reproducible that way. Here the device
 * is stopped as soon as it is open, before any buffer exists, so its thread
 * mixes nothing; the driver then asks for the callbacks itself, one period
 * (480 frames, 10 ms at the null backend's 48000 Hz) at a time, from the
 * scripted clock. The callback is raudio's own, through miniaudio's own entry
 * point (ma_device_handle_backend_data_callback), as tools/sound_probe.py
 * asks for it.
 */
#include "raudio.c"

void JonlibAudioClockStop(void)
{
    if (AUDIO.System.isReady) ma_device_stop(&AUDIO.System.device);
}

void JonlibAudioClockPump(unsigned periods)
{
    static float out[480*2];
    if (!AUDIO.System.isReady) return;
    for (unsigned i = 0; i < periods; i++) ma_device_handle_backend_data_callback(&AUDIO.System.device, out, NULL, 480);
}
