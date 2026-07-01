package main

import "core:math"
import rl "vendor:raylib"

RIPPLE_HISTORY_COUNT :: 60
MAGNITUDE_COUNT      :: 128
VERTEX_COUNT         :: 180 // Number of points used to render each closed visualizer loop

// Ripple_Frame stores the spectrum state of a single past frame.
Ripple_Frame :: struct {
    magnitudes: [MAGNITUDE_COUNT]f32,
    bass_boost: f32,
}

// Ripple_History maintains a history of past frames in a zero-allocation ring buffer.
Ripple_History :: struct {
    frames: [RIPPLE_HISTORY_COUNT]Ripple_Frame,
    head:   int,
    count:  int,
}

// ripple_history_push adds a new frame's spectral magnitude profile to the history.
ripple_history_push :: proc(rh: ^Ripple_History, mags: []f32) {
    frame: Ripple_Frame
    
    // Copy incoming magnitudes to the fixed-size array
    n := min(len(mags), MAGNITUDE_COUNT)
    for i in 0..<n {
        frame.magnitudes[i] = mags[i]
    }
    
    // Calculate bass energy (first 8 bins, covering ~20Hz to ~350Hz) to modulate scale.
    bass_sum: f32 = 0.0
    bass_bins := min(8, n)
    for i in 0..<bass_bins {
        bass_sum += frame.magnitudes[i]
    }
    if bass_bins > 0 {
        frame.bass_boost = bass_sum / f32(bass_bins)
    }
    
    rh.frames[rh.head] = frame
    rh.head = (rh.head + 1) % RIPPLE_HISTORY_COUNT
    if rh.count < RIPPLE_HISTORY_COUNT {
        rh.count += 1
    }
}

// generate_ripple_vertices calculates a set of 2D vertices representing an expanding, mutating shape.
// `age_index` is 0 (current/epicenter) to `count - 1` (oldest/screen-edge).
// Pre-allocated slice `vertices` is populated in-place.
generate_ripple_vertices :: proc(
    rh: ^Ripple_History,
    age_index: int,
    center: rl.Vector2,
    base_radius: f32,
    max_expansion: f32,
    rotation: f32,
    vertices: []rl.Vector2,
) {
    if rh.count == 0 || len(vertices) == 0 do return
    
    // Retrieve the frame index starting from the newest
    idx := (rh.head - 1 - age_index + RIPPLE_HISTORY_COUNT) % RIPPLE_HISTORY_COUNT
    frame := rh.frames[idx]
    
    // Normalized age: t = 0.0 at center, t = 1.0 at screen edge
    t := f32(age_index) / f32(RIPPLE_HISTORY_COUNT)
    
    // Expand the base circle outward based on age and its original bass level.
    // The bass boost creates a shockwave expansion when low frequencies spike.
    current_base := base_radius + frame.bass_boost * 6.0
    current_radius := current_base + t * max_expansion
    
    v_count := len(vertices)
    for i in 0..<v_count {
        // Distribute vertices evenly around 360 degrees
        theta := 2.0 * math.PI * f32(i) / f32(v_count - 1)
        
        // Mirror the spectrum symmetrically across the vertical axis for a clean, closed loop
        val := theta / math.PI
        if val > 1.0 do val = 2.0 - val
        
        // Map the mirrored angle to the frequency bin indices and linearly interpolate
        idx_f := val * f32(MAGNITUDE_COUNT - 1)
        idx_lower := int(math.floor(idx_f))
        idx_upper := min(idx_lower + 1, MAGNITUDE_COUNT - 1)
        frac := idx_f - f32(idx_lower)
        
        mag := (1.0 - frac) * frame.magnitudes[idx_lower] + frac * frame.magnitudes[idx_upper]
        
        // Damping reduces the deformity as the ripple approaches the screen edges
        damping := 1.0 - t * 0.6
        r := current_radius + mag * 100.0 * damping
        
        // Apply rotation to make the visualizer feel alive and rotating
        rot_theta := theta + rotation
        
        vertices[i] = rl.Vector2{
            center[0] + r * math.cos_f32(rot_theta),
            center[1] + r * math.sin_f32(rot_theta),
        }
    }
}
