# avis

avis - High-Performance Odin Audio Visualizer.

## Overview

`avis` is a lightweight, high-performance audio visualizer written in the Odin programming language. It captures system loopback audio or local files and renders responsive, color-shifting geometry utilizing Raylib. 

It links directly to the ALSA system monitor sink on Linux for crisp loopback audio capture, rendering smooth wave sweeps and an audio-reactive black ferrofluid-like core.

## Features

* **Audio Input Options:** Supports direct ALSA loopback capture from the system monitor output, or local file playback (.mp3, .wav).
* **Reactive Core Puddle:** Solid black center puddle overlaying a glowing white backing plate, morphing from a 6-pointed star at rest into 8 sharp needle-like spikes.
* **Outer Frequency Loops:** Rotating, color-shifting outer wave loops and a tight-orbit mini-wave ring that expand and morph dynamically to different audio frequency bins.
* **Dynamic Scaling:** Window is resizable, scaling all vector drawing coordinates and anti-aliasing dynamically.

## Usage

You can run the compiled binary directly to start the visualizer capturing default system audio output.

```bash
# Capture and visualize system audio output
./avis

# Play and visualize a local audio file (.mp3, .wav, etc.)
./avis -f path/to/music.mp3
# or
./avis --file path/to/music.mp3

# Check usage options
./avis --help
```

### Controls

`Esc`: Close window and cleanly terminate the audio capture threads.

`Resize`: The window can be resized at any time; geometry scales and anti-aliases dynamically.

## Installation

### Requirements

* Odin Compiler (latest version)
* Raylib
* Make
* ALSA development headers (Required for loopback capture):
  * Arch Linux  : `sudo pacman -S alsa-lib`
  * Debian/Ubuntu: `sudo apt install libasound2-dev`

### Configuration

Modify visual properties directly inside the flat source files:
* Core and wave sizes: [render.odin](render.odin)
* History queues and vertex counts: [geometry.odin](geometry.odin)

### Building

Compile the application:
```bash
make
```

Install to system:
```bash
sudo make install  # Defaults to /usr/local/bin
```

#### Maintenance

Clean build artifacts:
```bash
make clean
```

Uninstall from system:
```bash
sudo make uninstall
```

## Contributing

Contributions are welcome! If you'd like to contribute to this project, please fork the repository and submit a pull request.

## Author

Chad Humphries |
[Website](https://grunclepug.com/) |
[GitHub Profile](https://github.com/GrunclePug)

## Other Projects

Check out some of my other projects on GitHub: [Here](https://github.com/GrunclePug?tab=repositories)
