# Yutani-GPU-Particles v0.1   
GPU particle engine for Delphi 10+ using Raylib with OpenGL 4.3+ compute shaders. Hundreds of thousands to millions of particles, fully simulated on the GPU — zero per-particle CPU work after initialisation.     
    
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/LaMitaOne/Yutani-GPU-Particles)    
     
 on ryzen4500u was around 2,7m still fine at 60fps, rtx does a bit more...       
<img width="1391" height="745" alt="Unbenannt" src="https://github.com/user-attachments/assets/8770d1bb-cc25-4aa1-91fd-9de1dd8c3f8a" />
      
Features   


    GPU compute shader physics — all particle positions and velocities are evolved on the GPU via a compute shader writing to SSBOs. No CPU round-trip per frame, no per-particle loop on the host.
    Instanced triangle rendering — one instanced draw call renders every visible particle as a small camera-facing arrow that points along its velocity vector. Vertex color comes from velocity direction (rainbow) or per-element fixed colors (Stickman Scene).
    12 show modes — switchable at runtime via ComboBox:

Mode
	
Description
Lorenz	Chaotic Lorenz attractor (sigma/rho/beta adjustable)
Cube	Particles lerp into a 3D cube surface
Sphere	Fibonacci sphere distribution + slow rotation
Wave	3D sine-wave motion field
Galaxy	Keplerian orbital motion with spiral-arm wobble
Fountain	Gravity-driven fountain with floor bounce + respawn
Vortex	Tornado swirl, faster toward center
DNA Helix	Double-helix strand with rotation
Black Hole	Gravity well + tangential orbit + respawn at edge
Explode	Oscillating expand/collapse shell
Flow Field	Curl-noise approximation with wrap-around
Stickman Scene	3D diorama: sun, house with roof, trees, street, flowers, walking stickman — each element in its own color
 
    Smooth mode transitions — switching modes does not snap. Form modes use mix(pos, target, rate) to lerp particles from their current positions to the new pattern. Motion modes take over from current pos/vel directly.
    Mouse interaction — hold left mouse button in the render window to push nearby particles away from the cursor. Screen-to-world conversion is done manually via camera vectors (no GetMouseRay dependency).
    Adjustable particle pool — trackbar from 1K to 5M particles in 1K steps. Engine recreates with the new pool size on the fly. Tested at 5M particles / 33 FPS on a Ryzen 4500U (Vega 6 iGPU).
    Adjustable visible count — N x1000 slider controls how many of the pool are actually rendered (0–100%). Default is 1000 (all visible).
    Per-element coloring — Stickman Scene assigns each scene element a fixed color (sun=yellow, stickman=blue, house=brown, roof=red, trees=green, street=gray, flowers=pink, ground=dark green) stored in positions.w.
    Threaded Raylib rendering — Raylib runs in a background TThread, embedded as a child window inside a VCL TPanel. QPC-based frame pacing with hybrid Sleep(1)+spin-wait for exact FPS targeting.
    Raw OpenGL 4.3+ function loading — compute shader, SSBO, VAO, and instanced draw functions are loaded via wglGetProcAddress, bypassing rlgl wrappers that may be compiled out as no-ops in some raylib DLL builds.
    Embedded shader sources — all GLSL is embedded as AnsiString constants. No external shader files, no file IO, no path issues.
    No third-party dependencies — only requires Raylib (which you already have). No additional Delphi packages, no NuGet, no installers.

Files
File
	
Purpose
Yutani.Render.Particles.GPU.pas	GPU particle engine (compute + render shaders, SSBOs, VAO)
uParticleEngine.pas	Threaded VCL/Raylib wrapper (frame pacing, camera, mouse push)
Unit1.pas	VCL form with all controls (trackbars, ComboBox, buttons, labels)
 
 
Requirements

     Delphi 10.3 Rio or newer (tested on Delphi 12 / dcc64)
     Raylib bindings for Delphi (ray4delphi or equivalent)
     OpenGL 4.3+ capable GPU (compute shaders + SSBOs)
      
     
Part of Yutani https://github.com/LaMitaOne/Yutani-Building-better-worlds     
