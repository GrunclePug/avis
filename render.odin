package main

import "core:math"
import rl "vendor:raylib"

// render_frame clears the screen and draws the expanding ripples and pulsating core.
render_frame :: proc(
    rh: ^Ripple_History,
    width, height: i32,
    hue_offset: f32,
    rotation: f32,
) {
    // Curated sleek dark mode background
    rl.ClearBackground(rl.Color{10, 6, 18, 255})
    
    center := rl.Vector2{f32(width) / 2.0, f32(height) / 2.0}
    
    // Scale radii relative to the window dimensions
    base_radius   := f32(min(width, height)) * 0.03
    max_expansion := f32(min(width, height)) * 0.15
    
    // Allocate the vertex buffer dynamically from the thread-local temp arena
    vertices, err := make([]rl.Vector2, VERTEX_COUNT, context.temp_allocator)
    if err != nil do return
    
    // Draw rings from oldest to newest so younger rings render on top
    for i := rh.count - 1; i >= 0; i -= 1 {
        t := f32(i) / f32(RIPPLE_HISTORY_COUNT) // 0.0 (newest) to 1.0 (oldest)
        
        // Add a twist effect: older rings rotate progressively faster
        ring_rotation := rotation + t * 1.6
        
        generate_ripple_vertices(rh, i, center, base_radius, max_expansion, ring_rotation, vertices)
        
        v_count := len(vertices)
        for j in 0..<v_count-1 {
            frac := f32(j) / f32(v_count - 1)
            
            // Shift color hues around the ring, over time (hue_offset), and across ages (t)
            segment_hue := math.mod_f32(hue_offset + frac * 360.0 + t * 100.0, 360.0)
            
            // Quadratic opacity decay for soft dissipation towards the edges
            color := rl.ColorFromHSV(segment_hue, 0.85, 0.95)
            color.a = u8((1.0 - t) * (1.0 - t) * 230.0)
            
            // Draw segment
            thickness := 1.0 + (1.0 - t) * 2.5
            rl.DrawLineEx(vertices[j], vertices[j+1], thickness, color)
        }
        
        // Close the loop from the last vertex back to the first
        if v_count > 1 {
            segment_hue := math.mod_f32(hue_offset + 360.0 + t * 100.0, 360.0)
            color := rl.ColorFromHSV(segment_hue, 0.85, 0.95)
            color.a = u8((1.0 - t) * (1.0 - t) * 230.0)
            thickness := 1.0 + (1.0 - t) * 2.5
            rl.DrawLineEx(vertices[v_count-1], vertices[0], thickness, color)
        }
    }
    
    // Draw a pulsating, morphing mini-wave loop and a central solid dot in the center
    if rh.count > 0 {
        newest_idx := (rh.head - 1 + RIPPLE_HISTORY_COUNT) % RIPPLE_HISTORY_COUNT
        newest_frame := rh.frames[newest_idx]
        
        // --- 1. Sizing boundaries ---
        // The closest outer wave starts at wave_boundary.
        wave_boundary := base_radius + newest_frame.bass_boost * 6.0
        
        // The solid center dot expands mildly with the bass (shrunk by 30% and dampened to remain compact)
        core_radius := base_radius * 0.62 + newest_frame.bass_boost * 0.8
        
        // --- 2. Inner Mini-Wave Ring (Morphs and wiggles just like the outer waves) ---
        MINI_WAVE_VERTICES :: 90
        mini_vertices, err := make([]rl.Vector2, MINI_WAVE_VERTICES, context.temp_allocator)
        if err == nil {
            // Generate vertices for the mini-wave ring
            for i in 0..<MINI_WAVE_VERTICES {
                // Distribute vertices and rotate slowly in the opposite direction
                theta := f32(i) * (2.0 * math.PI / f32(MINI_WAVE_VERTICES)) - rotation * 0.5
                
                // Mirror the spectrum for vertical symmetry
                val := theta / math.PI
                if val < 0 do val += 2.0
                val = math.mod_f32(val, 2.0)
                if val > 1.0 do val = 2.0 - val
                
                // Linear interpolation of frequency bins
                idx_f := val * f32(MAGNITUDE_COUNT - 1)
                idx_lower := int(math.floor(idx_f))
                idx_upper := min(idx_lower + 1, MAGNITUDE_COUNT - 1)
                frac := idx_f - f32(idx_lower)
                
                mag := (1.0 - frac) * newest_frame.magnitudes[idx_lower] + frac * newest_frame.magnitudes[idx_upper]
                
                // Radius of the mini-wave (increased wiggling factor to make it dynamic and show interesting shapes)
                r := core_radius + mag * 35.0
                
                // Hard-clamp the radius so it sits tight to the core and stays far from the main waves
                // Max radius is limited to 45% of the total gap width to allow rich wiggles
                max_r := core_radius + (wave_boundary - core_radius) * 0.45
                min_r := core_radius + 0.3
                if r > max_r do r = max_r
                if r < min_r do r = min_r
                
                mini_vertices[i] = rl.Vector2{
                    center[0] + r * math.cos_f32(theta),
                    center[1] + r * math.sin_f32(theta),
                }
            }
            
            // Mini-wave transparent fill removed to keep the core area clean and free of background rainbows
            
            // Draw thick, beautiful neon mini-wave outline with shifting color sweep
            for i in 0..<MINI_WAVE_VERTICES {
                frac := f32(i) / f32(MINI_WAVE_VERTICES)
                seg_hue := math.mod_f32(hue_offset + frac * 360.0, 360.0)
                seg_color := rl.ColorFromHSV(seg_hue, 0.85, 0.95)
                seg_color.a = 220
                rl.DrawLineEx(mini_vertices[i], mini_vertices[(i + 1) % MINI_WAVE_VERTICES], 1.8, seg_color)
            }
        }
        
        // --- 3. High-Contrast Ferrofluid Plate Core ---
        // A. Shifting color aura and base white plate (the glowing backdrop)
        plate_glow := rl.ColorFromHSV(math.mod_f32(hue_offset, 360.0), 0.80, 0.95)
        plate_glow.a = 80
        rl.DrawCircleV(center, core_radius * 0.90, plate_glow)
        rl.DrawCircleV(center, core_radius * 0.82, rl.WHITE)
        
        // B. Overlaid Morphing Black Ferrofluid Core Blob
        // Increased to 96 vertices (4x resolution) to draw smooth, sharp fluid needles instead of blocky rectangles
        FERRO_VERTICES :: 96
        ferro_pts: [FERRO_VERTICES]rl.Vector2
        ferro_time := rotation * 4.0
        
        for i in 0..<FERRO_VERTICES {
            theta := f32(i) * (2.0 * math.PI / f32(FERRO_VERTICES))
            
            // Base radius of the ferrofluid blob
            base_r := core_radius * 0.32
            
            // 6-petaled symmetric geometric lobes (dampened so it wiggles mildly)
            lobes := math.cos_f32(theta * 6.0 + rotation * 2.0) * (core_radius * 0.03 + newest_frame.bass_boost * 0.1)
            
            // Solid body of the puddle (clamped so the center stays small and doesn't expand to a full circle)
            r_body := base_r + lobes
            max_body := core_radius * 0.40
            min_body := core_radius * 0.15
            if r_body > max_body do r_body = max_body
            if r_body < min_body do r_body = min_body
            
            // Get raw magnitude for this angle sector (mapping to 32 active bins for varied geometric spikes)
            mag := newest_frame.magnitudes[i % 32]
            
            // 8 sharp, needle spikes (using absolute sine raised to 4th power to make spikes extremely narrow needles)
            // High vertex resolution renders these as smooth, sharp points
            sin_val := math.abs(math.sin_f32(theta * 8.0 - rotation * 3.0))
            spikes := sin_val * sin_val * sin_val * sin_val * (mag * 15.0)
            
            // Add spikes on top of the clamped body
            r := r_body + spikes
            
            // Cap the final spikes to 0.70 of the core, so they never cover the outer white plate
            max_r := core_radius * 0.70
            if r > max_r do r = max_r
            
            ferro_pts[i] = rl.Vector2{
                center[0] + r * math.cos_f32(theta),
                center[1] + r * math.sin_f32(theta),
            }
        }
        
        // Render the black ferrofluid blob ON TOP of the white plate (counter-clockwise winding order so it fills solid black)
        for i in 0..<FERRO_VERTICES {
            rl.DrawTriangle(center, ferro_pts[(i + 1) % FERRO_VERTICES], ferro_pts[i], rl.BLACK)
        }
    }
}
