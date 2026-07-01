package main

import "core:math"

// hann_window calculates the Hann window weight for a given sample index `n` of a total length `N`.
hann_window :: proc(n, N: int) -> f32 {
    if N <= 1 do return 1.0
    return 0.5 * (1.0 - math.cos_f32(2.0 * math.PI * f32(n) / f32(N - 1)))
}

// bit_reverse reverses the bits of an integer `n` with a given bit width.
bit_reverse :: proc(n: int, bits: int) -> int {
    val := n
    rev := 0
    for _ in 0..<bits {
        rev = (rev << 1) | (val & 1)
        val >>= 1
    }
    return rev
}

// fft performs an in-place Radix-2 Cooley-Tukey Fast Fourier Transform.
// The length of slice `a` MUST be a power of two.
fft :: proc(a: []complex64) {
    n := len(a)
    if n <= 1 do return

    // Calculate number of bits required for N
    bits: uint = 0
    for (1 << bits) < n {
        bits += 1
    }
    
    // Bit-reversal permutation
    for i in 0..<n {
        rev := bit_reverse(i, int(bits))
        if i < rev {
            a[i], a[rev] = a[rev], a[i]
        }
    }

    // Cooley-Tukey decimation-in-time
    for step_len := 2; step_len <= n; step_len <<= 1 {
        ang := -2.0 * math.PI / f32(step_len)
        wlen := complex(math.cos_f32(ang), math.sin_f32(ang))
        for i := 0; i < n; i += step_len {
            w := complex64(1.0)
            half := step_len / 2
            for j in 0..<half {
                u := a[i + j]
                v := a[i + j + half] * w
                a[i + j] = u + v
                a[i + j + half] = u - v
                w *= wlen
            }
        }
    }
}

// complex_magnitude calculates the magnitude (absolute value) of a complex number.
complex_magnitude :: proc(c: complex64) -> f32 {
    r := real(c)
    i := imag(c)
    return math.sqrt_f32(r * r + i * i)
}
