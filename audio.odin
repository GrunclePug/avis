package main

import "base:runtime"
import "core:sync"
import "core:strings"
import "core:thread"
import "core:fmt"
import rl "vendor:raylib"

// ALSA C API declarations
snd_pcm_t :: struct {}

snd_pcm_stream_t :: enum i32 {
    PLAYBACK = 0,
    CAPTURE  = 1,
}

snd_pcm_format_t :: enum i32 {
    UNKNOWN = -1,
    S8 = 0,
    U8,
    S16_LE,
    S16_BE,
    U16_LE,
    U16_BE,
    S24_LE,
    S24_BE,
    U24_LE,
    U24_BE,
    S32_LE,
    S32_BE,
    U32_LE,
    U32_BE,
    FLOAT_LE,
    FLOAT_BE,
}

snd_pcm_access_t :: enum i32 {
    MMAP_INTERLEAVED = 0,
    MMAP_NONINTERLEAVED,
    MMAP_COMPLEX,
    RW_INTERLEAVED,
    RW_NONINTERLEAVED,
}

foreign import alsa "system:asound"

@(default_calling_convention="c")
foreign alsa {
    snd_pcm_open :: proc(pcm: ^^snd_pcm_t, name: cstring, stream: snd_pcm_stream_t, mode: i32) -> i32 ---
    snd_pcm_close :: proc(pcm: ^snd_pcm_t) -> i32 ---
    snd_pcm_prepare :: proc(pcm: ^snd_pcm_t) -> i32 ---
    snd_pcm_set_params :: proc(
        pcm: ^snd_pcm_t,
        format: snd_pcm_format_t,
        access: snd_pcm_access_t,
        channels: u32,
        rate: u32,
        soft_resample: i32,
        latency: u32,
    ) -> i32 ---
    snd_pcm_readi :: proc(pcm: ^snd_pcm_t, buffer: rawptr, size: uint) -> int ---
    snd_strerror :: proc(errnum: i32) -> cstring ---
}

// libc declarations for popen (capturing pactl output)
FILE :: struct {}

foreign import libc "system:c"

@(default_calling_convention="c")
foreign libc {
    popen  :: proc(command, type: cstring) -> ^FILE ---
    pclose :: proc(stream: ^FILE) -> i32 ---
    fgets  :: proc(str: [^]u8, n: i32, stream: ^FILE) -> [^]u8 ---
}

// Ring_Buffer is a thread-safe circular buffer for storing raw audio samples.
Ring_Buffer :: struct {
    data: []f32,
    write_idx: u32,
}

// Audio_Context manages active audio resources (ALSA microphone capture or Raylib music streaming).
Audio_Context :: struct {
    ring_buffer:     Ring_Buffer,
    
    // ALSA Capture State
    pcm_handle:      ^snd_pcm_t,
    capture_thread:  ^thread.Thread,
    is_capturing:    bool,
    
    // Raylib Music State
    music:           rl.Music,
    is_playing_file: bool,
}

// Package-level global context required for the Raylib audio callback
g_audio_context: ^Audio_Context = nil

// ring_buffer_init allocates memory for the ring buffer.
ring_buffer_init :: proc(rb: ^Ring_Buffer, size: int, allocator := context.allocator) {
    rb.data = make([]f32, size, allocator)
    rb.write_idx = 0
}

// ring_buffer_free deallocates memory for the ring buffer.
ring_buffer_free :: proc(rb: ^Ring_Buffer, allocator := context.allocator) {
    delete(rb.data, allocator)
}

// ring_buffer_push inserts samples into the ring buffer atomically.
ring_buffer_push :: proc(rb: ^Ring_Buffer, samples: []f32) {
    size := u32(len(rb.data))
    if size == 0 do return
    
    w := sync.atomic_load(&rb.write_idx)
    for s in samples {
        rb.data[w] = s
        w = (w + 1) % size
    }
    sync.atomic_store(&rb.write_idx, w)
}

// ring_buffer_get_latest copies the most recent `n` samples from the ring buffer.
ring_buffer_get_latest :: proc(rb: ^Ring_Buffer, dest: []f32) {
    size := u32(len(rb.data))
    if size == 0 do return
    
    n := u32(len(dest))
    w := sync.atomic_load(&rb.write_idx)
    
    start := (w + size - n) % size
    for i in 0..<n {
        dest[i] = rb.data[(start + i) % size]
    }
}

// get_default_sink_monitor queries PulseAudio/PipeWire for the default playback sink
// and formats it as an ALSA pulse monitor device identifier (e.g. pulse:alsa_output...monitor).
get_default_sink_monitor :: proc(allocator := context.allocator) -> (string, bool) {
    pipe := popen("pactl get-default-sink", "r")
    if pipe == nil do return "", false
    defer pclose(pipe)
    
    buf: [512]u8
    res := fgets(&buf[0], size_of(buf), pipe)
    if res == nil do return "", false
    
    out := string(buf[:])
    idx := strings.index_byte(out, 0)
    if idx >= 0 {
        out = out[:idx]
    }
    out = strings.trim_space(out)
    
    if len(out) == 0 do return "", false
    
    pulse_device := strings.concatenate({"pulse:", out, ".monitor"}, allocator)
    return pulse_device, true
}

// audio_init initializes either ALSA microphone capture or Raylib music file playback.
audio_init :: proc(ctx: ^Audio_Context, file_path: string) -> bool {
    g_audio_context = ctx
    
    // Use an 8192-sample buffer to allow plenty of room for FFT lookups.
    ring_buffer_init(&ctx.ring_buffer, 8192)
    
    if file_path != "" {
        if !rl.IsAudioDeviceReady() {
            rl.InitAudioDevice()
        }
        
        path_cstr := strings.clone_to_cstring(file_path, context.temp_allocator)
        ctx.music = rl.LoadMusicStream(path_cstr)
        if !rl.IsAudioStreamValid(ctx.music.stream) {
            ring_buffer_free(&ctx.ring_buffer)
            return false
        }
        
        rl.PlayMusicStream(ctx.music)
        rl.AttachAudioStreamProcessor(ctx.music.stream, raylib_audio_callback)
        ctx.is_playing_file = true
        return true
    } else {
        device_name := "default"
        monitor_dev, has_monitor := get_default_sink_monitor(context.temp_allocator)
        if has_monitor {
            device_name = monitor_dev
        }
        
        fmt.printf("AVIS: Opening capture device: %s\n", device_name)
        
        device_cstr := strings.clone_to_cstring(device_name, context.temp_allocator)
        res := snd_pcm_open(&ctx.pcm_handle, device_cstr, .CAPTURE, 0)
        if res < 0 {
            if device_name != "default" {
                fmt.println("AVIS: Failed to open pulse monitor, falling back to 'default' capture...")
                res = snd_pcm_open(&ctx.pcm_handle, "default", .CAPTURE, 0)
            }
            if res < 0 {
                ring_buffer_free(&ctx.ring_buffer)
                return false
            }
        }
        
        // Config: 1 channel, 44100 Hz, Float Little Endian, 50ms latency
        res = snd_pcm_set_params(ctx.pcm_handle, .FLOAT_LE, .RW_INTERLEAVED, 1, 44100, 1, 50000)
        if res < 0 {
            snd_pcm_close(ctx.pcm_handle)
            ring_buffer_free(&ctx.ring_buffer)
            return false
        }
        
        ctx.is_capturing = true
        ctx.capture_thread = thread.create(capture_thread_proc)
        if ctx.capture_thread == nil {
            snd_pcm_close(ctx.pcm_handle)
            ring_buffer_free(&ctx.ring_buffer)
            ctx.is_capturing = false
            return false
        }
        
        ctx.capture_thread.data = ctx
        thread.start(ctx.capture_thread)
        return true
    }
}

// audio_update keeps the file streams fed if playing from file.
audio_update :: proc(ctx: ^Audio_Context) {
    if ctx.is_playing_file {
        rl.UpdateMusicStream(ctx.music)
    }
}

// audio_shutdown releases all system and streaming audio resources.
audio_shutdown :: proc(ctx: ^Audio_Context) {
    if ctx.is_playing_file {
        rl.DetachAudioStreamProcessor(ctx.music.stream, raylib_audio_callback)
        rl.UnloadMusicStream(ctx.music)
        rl.CloseAudioDevice()
    }
    
    if ctx.is_capturing {
        ctx.is_capturing = false
        // Close the PCM handle first to unblock the capture loop immediately
        snd_pcm_close(ctx.pcm_handle)
        if ctx.capture_thread != nil {
            thread.join(ctx.capture_thread)
            thread.destroy(ctx.capture_thread)
        }
    }
    
    ring_buffer_free(&ctx.ring_buffer)
    g_audio_context = nil
}

// capture_thread_proc runs in a background thread to read raw capture frames from ALSA.
capture_thread_proc :: proc(t: ^thread.Thread) {
    ctx := (^Audio_Context)(t.data)
    if ctx == nil do return
    
    buf: [256]f32
    
    for ctx.is_capturing {
        // Read 256 samples (approx 5.8ms block)
        res := snd_pcm_readi(ctx.pcm_handle, &buf[0], 256)
        if res < 0 {
            // EPIPE is -32 (overrun), recover the device
            snd_pcm_prepare(ctx.pcm_handle)
            continue
        }
        
        if res > 0 {
            ring_buffer_push(&ctx.ring_buffer, buf[:res])
        }
    }
}

// raylib_audio_callback is called by Raylib's playback thread to feed/process audio samples.
raylib_audio_callback :: proc "c" (bufferData: rawptr, frames: u32) {
    context = runtime.default_context()
    if bufferData == nil || frames == 0 do return
    ctx := g_audio_context
    if ctx == nil do return

    channels := int(ctx.music.stream.channels)
    total_samples := int(frames) * channels
    samples := (([^]f32)(bufferData))[:total_samples]
    
    MAX_FRAMES :: 2048
    mono_samples: [MAX_FRAMES]f32
    n_frames := int(frames)
    if n_frames > MAX_FRAMES do n_frames = MAX_FRAMES
    
    if channels == 1 {
        ring_buffer_push(&ctx.ring_buffer, samples[:n_frames])
    } else {
        for i in 0..<n_frames {
            sum: f32 = 0.0
            for c in 0..<channels {
                sum += samples[i * channels + c]
            }
            mono_samples[i] = sum / f32(channels)
        }
        ring_buffer_push(&ctx.ring_buffer, mono_samples[:n_frames])
    }
}
