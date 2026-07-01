package main

import "core:fmt"
import "core:os"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

VERSION :: #config(VERSION, "0.1.0")

// Config holds command-line arguments configuration.
Config :: struct {
    file_path: string,
}

// parse_args parses the CLI options and returns the configuration.
parse_args :: proc() -> (Config, bool) {
    config: Config
    args := os.args[1:]
    
    i := 0
    for i < len(args) {
        arg := args[i]
        if arg == "-h" || arg == "--help" {
            fmt.printf("AVIS - High-Performance Odin Audio Visualizer v%s\n", VERSION)
            fmt.println("Usage:")
            fmt.println("  avis [options] [audio_file]")
            fmt.println("Options:")
            fmt.println("  -f, --file <path>   Path to local audio file (.mp3, .wav) to play and visualize.")
            fmt.println("  -h, --help          Show this help message.")
            return config, false
        } else if arg == "-f" || arg == "--file" {
            if i + 1 < len(args) {
                config.file_path = args[i + 1]
                i += 2
            } else {
                fmt.eprintln("Error: Missing file path after option", arg)
                return config, false
            }
        } else {
            // Check if it's a positional argument and doesn't start with '-'
            if arg[0] != '-' {
                config.file_path = arg
                i += 1
            } else {
                fmt.eprintf("Error: Unknown option %s\n", arg)
                return config, false
            }
        }
    }
    
    return config, true
}

main :: proc() {
    config, ok := parse_args()
    if !ok {
        os.exit(1)
    }

    // Configure window flags: Resizable and Anti-Aliased lines (MSAA 4X)
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT})
    rl.InitWindow(1280, 720, "AVIS - Odin Audio Visualizer")
    rl.SetTargetFPS(60)

    // Initialize audio system
    audio_ctx: Audio_Context
    if !audio_init(&audio_ctx, config.file_path) {
        if config.file_path != "" {
            fmt.eprintf("Error: Failed to load local audio file: %s\n", config.file_path)
        } else {
            fmt.eprintln("Error: Failed to open default audio capture device.")
            fmt.eprintln("Please ensure you have an active recording device (mic/monitor) and PulseAudio/PipeWire is active.")
        }
        rl.CloseWindow()
        os.exit(1)
    }

    // DSP/FFT State
    // N = 1024 is ideal: covers ~23ms of audio per window, giving sharp frequency resolution.
    FFT_SIZE :: 1024
    raw_samples: [FFT_SIZE]f32
    fft_buffer:  [FFT_SIZE]complex64
    magnitudes:  [FFT_SIZE / 2]f32 // Smooth frequency bins persisted across frames

    // Geometry Ripple State
    ripple_history: Ripple_History
    
    hue_offset: f32 = 0.0
    rotation:   f32 = 0.0

    // Main frame loop
    for !rl.WindowShouldClose() {
        // Reset the thread-local temporary allocator arena for zero-heap-allocation draw frames.
        free_all(context.temp_allocator)

        dt := rl.GetFrameTime()

        // Update the audio stream buffers (essential for Raylib file playback)
        audio_update(&audio_ctx)

        // Pull the most recent raw PCM samples from our thread-safe ring buffer
        ring_buffer_get_latest(&audio_ctx.ring_buffer, raw_samples[:])

        // Apply Hann windowing to prevent spectral leakage and convert to complex domain
        for i in 0..<FFT_SIZE {
            w := hann_window(i, FFT_SIZE)
            fft_buffer[i] = complex(raw_samples[i] * w, f32(0.0))
        }

        // Perform in-place Radix-2 Cooley-Tukey FFT
        fft(fft_buffer[:])

        // Calculate and smooth magnitudes
        for i in 0..<FFT_SIZE / 2 {
            mag := complex_magnitude(fft_buffer[i])
            
            // Apply frequency-dependent scaling (ramp up higher frequencies)
            freq_boost := 1.0 + f32(i) * 0.012
            target_mag := mag * freq_boost
            
            // Temporal smoothing (EMA filter) to prevent high-frequency visual jitter
            magnitudes[i] = magnitudes[i] * 0.82 + target_mag * 0.18
        }

        // Push the lower/middle range of frequency magnitudes (up to 128 bins, or ~5.5kHz)
        ripple_history_push(&ripple_history, magnitudes[:MAGNITUDE_COUNT])

        // Evolve colors and rotation
        hue_offset = math.mod_f32(hue_offset + dt * 25.0, 360.0) // Rotate rainbow colors
        rotation   = math.mod_f32(rotation + dt * 0.12, 2.0 * math.PI)

        // Draw Frame
        rl.BeginDrawing()
        
        render_frame(&ripple_history, rl.GetScreenWidth(), rl.GetScreenHeight(), hue_offset, rotation)
        
        // Draw Diagnostics
        rl.DrawFPS(10, 10)
        if audio_ctx.is_playing_file {
            rl.DrawText("Source: File Loopback (Raylib)", 10, 32, 16, rl.Color{200, 200, 200, 255})
            rl.DrawText(strings.clone_to_cstring(config.file_path, context.temp_allocator), 10, 52, 12, rl.Color{160, 160, 160, 255})
        } else {
            rl.DrawText("Source: Default Audio Capture (Miniaudio)", 10, 32, 16, rl.Color{200, 200, 200, 255})
        }
        
        rl.EndDrawing()
    }

    // Clean shutdown
    audio_shutdown(&audio_ctx)
    rl.CloseWindow()
}
