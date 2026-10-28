# Yutani-GPU-Particles v0.2   
GPU particle engine for Delphi 10+ using Raylib with OpenGL 4.3+ compute shaders. Hundreds of thousands to millions of particles, fully simulated on the GPU — zero per-particle CPU work after initialisation.     
    
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/LaMitaOne/Yutani-GPU-Particles)    
      
Sample video:  https://youtu.be/QT0Lkt7IVJI      
     
 on ryzen4500u around 2,7m still fine @ 60fps, rtx 2060s does bit more... 15m. A 5090 maybe can do even up to 100m or more? no idea      
<img width="1391" height="745" alt="Unbenannt" src="https://github.com/user-attachments/assets/8770d1bb-cc25-4aa1-91fd-9de1dd8c3f8a" />
      
Features   


    GPU compute shader physics — all particle positions and velocities are evolved on the GPU via a compute shader writing to SSBOs. No CPU round-trip per frame, no per-particle loop on the host.
    Instanced triangle rendering — one instanced draw call renders every visible particle as a small camera-facing arrow that points along its velocity vector. Vertex color comes from velocity direction (rainbow) or per-element fixed colors (Stickman Scene).
    60 active particle modes — switchable at runtime via ComboBox (featuring 12 legacy show modes and 48 environment/atmospheric simulation styles).    
    Global forces integration — real-time adjustable global wind (globalWind) and gravity (globalGravity) vec3 parameters that natively affect all active particle calculations.
    Cinematic HDR pipeline — integrated global hdrMultiplier to amplify particle vertex emission brightness, ready for screen-space bloom filters and post-processing stacks.
    Dynamic runtime uniform styling — host-controlled uniform parameter mappings allowing custom color changing (SetEmColor RGBA) and sizing overlays (SetEmSize) across all new environment modes.
    Smooth mode transitions — switching modes does not snap. Form modes use mix(pos, target, rate) to lerp particles from their current positions to the new pattern. Motion modes take over from current pos/vel directly.
    Mouse interaction — hold left mouse button in the render window to push nearby particles away from the cursor. Screen-to-world conversion is done manually via camera vectors (no GetMouseRay dependency).
    Adjustable particle pool — trackbar from 1K to 5M particles in 1K steps. Engine recreates with the new pool size on the fly. Tested at 5M particles / 33 FPS on a Ryzen 4500U (Vega 6 iGPU) and 15,3million at 60fps on rtx2060s.
    Adjustable visible count — N x1000 slider controls how many of the pool are actually rendered (0–100%). Default is 1000 (all visible).
    Per-element coloring — Stickman Scene assigns each scene element a fixed color (sun=yellow, stickman=blue, house=brown, roof=red, trees=green, street=gray, flowers=pink, ground=dark green) stored in positions.w. Emitter modes route into a custom dynamic override slot.
    Threaded Raylib rendering — Raylib runs in a background TThread, embedded as a child window inside a VCL TPanel. QPC-based frame pacing with hybrid Sleep(1)+spin-wait for exact FPS targeting.
    Raw OpenGL 4.3+ function loading — compute shader, SSBO, VAO, and instanced draw functions are loaded via wglGetProcAddress, bypassing rlgl wrappers that may be compiled out as no-ops in some raylib DLL builds.
    Embedded shader sources — all GLSL is embedded as AnsiString constants. No external shader files, no file IO, no path issues.
    No third-party dependencies — only requires Raylib (which you already have). No additional Delphi packages, no NuGet, no installers.   

        

Mode Name   Description        
0	Lorenz	Chaotic Lorenz attractor (sigma/rho/beta adjustable)        
1	Cube	Particles lerp into a 3D cube surface        
2	Sphere	Fibonacci sphere distribution + slow rotation        
3	Wave	3D sine-wave motion field        
4	Galaxy	Keplerian orbital motion with spiral-arm wobble        
5	Fountain	Gravity-driven fountain with floor bounce + respawn        
6	Vortex	Tornado swirl, faster toward center        
7	DNA Helix	Double-helix strand with rotation        
8	Black Hole	Gravity well + tangential orbit + respawn at edge        
9	Explode	Oscillating expand/collapse shell        
10	Flow Field	Curl-noise approximation with wrap-around        
11	Stickman Scene	3D diorama: sun, house with roof, trees, street, flowers, walking stickman — each element in its own fixed color        
12	Fog	Volumetric slow upward and lateral sin drift with boundary wrapping        
13	Fire	Turbulent upward thermal simulation with localized swirling        
14	Rain	Constant high-velocity gravity down-stream with automated top respawn        
15	Snow	Lightweight falling crystal structure with side-to-side air sway        
16	Smoke	Upward expanding expanding vapor trail with horizontal draft variations        
17	Explosion	One-shot uniform radial outward physics burst combined with linear gravity        
18	Sparks	Fast high-velocity directional directional bursts with steep gravity arcs        
19	Fountain2	Isolated source particle stream with custom floor velocity resets        
20	Storm	High-velocity chaotic 3D flow field with strict spatial region wrapping        
21	Dust	Ultra-slow environmental ambient micro-particles drifting in space        
22	Ants	Ground-level bounded 2D random walks locked strictly to the floor plane        
23	BlackGoo	Heavy viscous fluid dripping logic with moderate kinetic velocity drag        
24	Bubbles	Fluid buoyant medium upward rise with cyclic frequency wobble physics        
25	Fireflies	Organic slow wanderers featuring velocity-driven simulated glow pulses        
26	Leaves	Aerodynamic falling leaf structure with active rotational sway curves        
27	Energy	Destructive field crackle expanding and pulsing around the coordinate origin        
28	Plasma	Electric energy arcs combining tangential magnetic pull and random noise        
29	Lightning	Multi-directional jagged fast random-walk paths replicating a strobe bolt        
30	Ash	Cooling cinder fragments floating downwards with velocity color translations        
31	Debris	Fractured mass chunks exploding outwards under heavy gravity loads        
32	Steam	Expanding hot thermal vapor dissipation lifting and drifting laterally        
33	SnowDrift	Dynamic drift particles that fall and permanently freeze upon floor contact        
34	Insects	Chaotic swarming loop matching rapid wing flutter and flock centering        
35	Swarm	High-fidelity boids-style steering centering and wandering vectors        
36	Beam	Concentrated high-intensity sparkle shower falling vertically from above        
37	Portal	Swirling particle disc path locked entirely to the horizontal XZ plane        
38	Crystal	Inward grid drift vectors that freeze solid at a specific radius barrier        
39	PixieDust	Magical glowing path track featuring hyper-sharp frequency shimmers        
40	GhostMist	Eerie low-velocity translucent vapor with wave-modulated opacity maps        
41	Comet	Deep-space interstellar debris drifting inward from distant boundaries        
42	Shockwave	Rapidly expanding ground ring expanding outwards from the center        
43	RainSplash	High-impact ground impact splashing tracking tiny reflective velocity bounces        
44	LavaBubble	Slow dense magma updraft rising, popping at peak, and resetting        
45	StarField	Deep background stellar array with individual twinkle variables        
46	Nebula	Interstellar cloud arrays shifting under slow wave-modulated formulas        
47	Tornado	Massive 3D atmospheric vortex funnel expanding outwards with vertical lift        
48	Glow	Expansive pulsing radial light halo with soft breathing limits        
49	VolLight	Dynamic volumetric god-ray beam structures shimmering upwards        
50	Sandstorm	Violent horizontal wind streams driving dense environmental sand lines        
51	Hailstorm	Solid heavy ice physics dropping rapidly and executing hard ground rebounds        
52	Whirlpool	Aquatic vortex mechanics spiraling recursively inward along the XZ plane        
53	Mushroom	Complex nuclear displacement: vertical column column rise turning into a sprawling cap        
54	SmokeColumn	Solid continuous vertical smoke line processing localized air draft wobbles        
55	BlackSmoke	Heavy dense carbon-clogged exhaust rising with low kinetic speeds        
56	EngineExhaust	High-thrust jet afterburner expansion with dissipation parameters        
57	SparkTrail	Classic sparkler emission path tracking individual gravitational decay        
58	MagicMissile	High-speed tracking projectile trace featuring a trailing spiral trail        
59	Clouds	Advanced 3D Curl Noise fluidics simulation. Uses finite differences to solve a divergence-free velocity field, creating authentic volumetric gas swirls without clumping
  
 
 
Requirements

     Delphi 10.3 Rio or newer (tested on Delphi 12 / dcc64)
     Raylib bindings for Delphi (ray4laz or equivalent)
     OpenGL 4.3+ capable GPU (compute shaders + SSBOs)

based on Raylib GPU Particles by arceryz    
   https://github.com/arceryz/raylib-gpu-particles                 
     
Part of Yutani https://github.com/LaMitaOne/Yutani-Building-better-worlds     
