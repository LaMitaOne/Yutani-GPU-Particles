{*******************************************************************************
  uParticleEngine  - Yutani GPU Particle Light VCL Wrapper
********************************************************************************
  Threaded VCL Raylib wrapper for the Yutani.Render.Particles.GPU v3.0 engine.

  This wrapper exposes the new modular emitter API of the GPU engine.
  All legacy show-mode setters (SetMode, SetUseShowMode, SetSigma, SetRho,
  SetBeta) have been REMOVED - the engine now runs exclusively in multi-emitter
  mode. The host calls CreateFireEmitter / CreateExplosionEmitter / etc. or
  AddEmitter directly with a TYutaniEmitterData struct.

  Preset helpers build a TYutaniEmitterData with the right modular parameters
  (gravity, drag, curl noise, vortex, radial, color curves, blend mode) so
  fire, smoke, sparks, rain, etc. can be spawned in one line. They use the
  same modular emitter struct as custom emitters - no special etype branches.

  Author: Lara Miriam Tamy Reschke / LamitaOne
*******************************************************************************}

unit uParticleEngine;

interface

uses
  System.SysUtils, System.Types, System.Classes, System.Math, System.SyncObjs,
  Winapi.Windows, Winapi.MMSystem, Vcl.Controls, Raylib, rlgl, RayMath,
  Yutani.Render.Particles.GPU,
  Yutani.Render.ParticlePhysics;

const
  SPIN_THRESHOLD_NS = 2000000;
  DEFAULT_PARTICLE_COUNT = 512000;  // 500K default

type
  THighResTimer = record
    Frequency: Int64;
    procedure Init;
    function GetTicks: Int64; inline;
    procedure HybridWaitUntil(const ATargetTicks, ASpinNanoseconds: Int64);
  end;

  TParticleEngine = class(TThread)
  private
    FParentHandle: HWND;
    FRaylibWnd: HWND;
    FTargetFPS: Integer;
    FRealFPS: Integer;
    FActive: Boolean;
    FWidth, FHeight: Integer;
    { Pending dimension change requested by the VCL thread (FormResize). The
      engine thread picks this up at the top of the next frame and calls
      Raylib's SetWindowSize + adjusts the GL viewport. We MUST NOT call
      SetWindowSize from the VCL thread because Raylib's window-management
      API is not thread-safe (it touches the GL framebuffer + window
      message pump) and would race with EndDrawing() on the engine thread. }
    FPendingWidth:     Integer;
    FPendingHeight:    Integer;
    FPendingResize:    Boolean;
    FParticles: TYutaniParticleEngine;
    FCamera: TCamera3D;
    FDesiredParticleCount: Integer;
    { Mouse state for camera orbit/pan/zoom controls }
    FLastMouseX:  Integer;
    FLastMouseY:  Integer;
    FMouseInit:   Boolean;

    { Desired parameter values - stored independently of FParticles so that
      when the engine is recreated (e.g. when the user picks a new pool size),
      the current slider values can be pushed to the fresh engine. }
    FDesiredParticleScale:   Single;
    FDesiredTimeScale:       Single;
    FDesiredInstancesX1000:  Single;
    FDesiredBlendMode:       TYutaniBlendMode;
    FDesiredGlobalWind:      TVector3;
    FDesiredGlobalGravity:   TVector3;
    FDesiredHDRMultiplier:   Single;
    FDesiredOnEmitterExpired: TEmitterExpiredEvent;

    procedure RenderScene;
    procedure SetActive(const Value: Boolean);
    procedure PushDesiredValuesToEngine;
    { Camera controls: orbit around target, pan target+camera, zoom in/out }
    procedure OrbitCamera(YawDelta, PitchDelta: Single);
    procedure PanCamera(DX, DY: Single);
    procedure ZoomCamera(WheelDelta: Single);
    procedure CheckMousePush;
  protected
    procedure Execute; override;
  public
    constructor Create(AParentHandle: HWND;
                       ANumParticles: Integer = DEFAULT_PARTICLE_COUNT);
    destructor Destroy; override;
    procedure StartEngine;
    procedure StopEngine;

    procedure Restart;
    procedure Reset;

    { Engine parameter setters - push to live engine AND cache as desired }
    procedure SetParticleScale(Value: Single);
    procedure SetTimeScale(Value: Single);
    procedure SetInstancesX1000(Value: Single);
    procedure SetBlendMode(Value: TYutaniBlendMode);

    procedure SetFPS(const FPS: Integer);
    procedure SetDimensions(const W, H: Integer);
    procedure SetCamera(const Pos, Target: TVector3; Fovy: Single);

    { Global forces (applied to ALL particles after per-emitter behavior) }
    procedure SetGlobalWind(const AWind: TVector3);
    procedure SetGlobalGravity(const AGravity: TVector3);
    procedure SetHDRMultiplier(AMultiplier: Single);
    { Physics-Bridge forwarders }
    procedure SetPhysicsBridge(const ABridge: IParticlePhysicsBridge);
    procedure SetPhysicsSampleRate(ARate: Integer);

    { Sprite atlas - bind a 4x4 atlas texture so per-emitter TextureIndex
      selects a sprite cell. Pass 0 to disable and use the procedural radial
      gradient fallback. }
    procedure SetSpriteAtlas(ATextureID: Cardinal);
    procedure ClearSpriteAtlas;

    { === Generic emitter API - pass a fully-built TYutaniEmitterData === }
    function AddEmitter(const AData: TYutaniEmitterData): Integer;
    function RemoveEmitter(EmitterID: Integer): Boolean;
    procedure ClearEmitters;
    function GetEmitterCount: Integer;
    function GetEmitter(EmitterID: Integer; out AEmitter: TYutaniEmitterData): Boolean;
    function SetEmitterActive(EmitterID: Integer; AActive: Boolean): Boolean;
    function SetEmitterStartColor(EmitterID: Integer; const AColor: TColorB): Boolean;
    function SetEmitterEndColor(EmitterID: Integer; const AColor: TColorB): Boolean;
    function SetEmitterGlow(EmitterID: Integer; AGlow: Single): Boolean;
    function SetEmitterTrailStrength(EmitterID: Integer; AStrength: Single): Boolean;
    function SetEmitterUseColorOverride(EmitterID: Integer; AUse: Boolean): Boolean;
    function SetEmitterLifeMode(EmitterID: Integer; AMode: TYutaniLifeMode): Boolean;
    function SetEmitterRegion(EmitterID: Integer;
      const ARegionMin, ARegionMax: TVector3): Boolean;
    function SetEmitterOrigin(EmitterID: Integer; const AOrigin: TVector3): Boolean;
    function SetEmitterFromTo(EmitterID: Integer;
      const AFromPos, AToPos: TVector3): Boolean;

    { Materialize / Dematerialize presets }
    procedure EmitMaterializeCube(const TargetPos: TVector3; VoxelSize: Single = 0.1);
    procedure EmitDematerializeCube(const SourcePos: TVector3; VoxelSize: Single = 0.1);
    procedure EmitMaterializeMesh(const TargetPos: TVector3; const Mesh: TMesh);
    procedure EmitDematerializeMesh(const SourcePos: TVector3; const Mesh: TMesh);

    { ============================================================
      PRESET EMITTER FACTORIES
      Each helper builds a TYutaniEmitterData with the right modular
      parameters for a classic effect. They all return the new emitter
      ID (or -1 on failure). The host can tweak the returned emitter
      further via SetEmitter* calls.
      ============================================================ }
    { Box of fire particles rising upward, turbulent, hot color shift.
      Additive blend for glow. }
    function CreateFireEmitter(const AOrigin: TVector3; ARadius: Single;
      AParticleCount: Integer = 4000): Integer;
    { One-shot explosion: outward burst + gravity + smoke fade.
      Additive blend, OneShotAutoRemove so the host can chain sub-emitters. }
    function CreateExplosionEmitter(const AOrigin: TVector3; ARadius: Single;
      AParticleCount: Integer = 3000): Integer;
    { Slow upward gray smoke with curl-noise turbulence. Alpha blend. }
    function CreateSmokeEmitter(const AOrigin: TVector3; ARadius: Single;
      AParticleCount: Integer = 3000): Integer;
    { Fast outward sparks with gravity + bright trail. Additive blend. }
    function CreateSparksEmitter(const AOrigin: TVector3; ARadius: Single;
      AParticleCount: Integer = 2000): Integer;
    { Vertical rain from a box region, gravity strong, respawn at top.
      Alpha blend. }
    function CreateRainEmitter(const ARegionMin, ARegionMax: TVector3;
      AParticleCount: Integer = 8000): Integer;
    { Slow downward snow with sway. Alpha blend. }
    function CreateSnowEmitter(const ARegionMin, ARegionMax: TVector3;
      AParticleCount: Integer = 4000): Integer;
    { Curl-noise magic shimmer around an origin. Additive blend + glow. }
    function CreateMagicEmitter(const AOrigin: TVector3; ARadius: Single;
      AParticleCount: Integer = 3000): Integer;
    { Vortex swirling around an axis (default up) + slight pull to origin. }
    function CreateVortexEmitter(const AOrigin, AAxis: TVector3;
      ARadius: Single; AParticleCount: Integer = 4000): Integer;
    { Gravity fountain that respawns at the origin. }
    function CreateFountainEmitter(const AOrigin: TVector3;
      AParticleCount: Integer = 4000): Integer;
    { Cone thruster (e.g. rocket engine). Direction is along ADirection. }
    function CreateThrusterEmitter(const AOrigin, ADirection: TVector3;
      AConeAngle: Single; AParticleCount: Integer = 3000): Integer;

  private
    function  GetOnEmitterExpired: TEmitterExpiredEvent;
    procedure SetOnEmitterExpired(AValue: TEmitterExpiredEvent);
  public
    { OnEmitterExpired event forward - lets the host chain sub-emitters. }
    property OnEmitterExpired: TEmitterExpiredEvent read GetOnEmitterExpired write SetOnEmitterExpired;

    property RealFPS: Integer read FRealFPS;
    property TargetFPS: Integer read FTargetFPS;
    property Active: Boolean read FActive write SetActive;
    property ParticleEngine: TYutaniParticleEngine read FParticles;
    property DesiredParticleCount: Integer read FDesiredParticleCount;
  end;

implementation

{ Helper: make a TColorB from raw RGB bytes. Avoids binding-dependent
  ColorAlpha signatures. }
function MakeCol(r, g, b, a: Byte): TColorB;
begin
  Result.r := r; Result.g := g; Result.b := b; Result.a := a;
end;

{ THighResTimer }

procedure THighResTimer.Init;
begin
  if not QueryPerformanceFrequency(Frequency) then
    Frequency := 0;
end;

function THighResTimer.GetTicks: Int64;
begin
  QueryPerformanceCounter(Result);
end;

procedure THighResTimer.HybridWaitUntil(const ATargetTicks, ASpinNanoseconds: Int64);
var
  SpinTicks, Remaining: Int64;
begin
  if Frequency = 0 then Exit;
  SpinTicks := (ASpinNanoseconds * Frequency) div 1000000000;
  Remaining := ATargetTicks - GetTicks;
  while Remaining > SpinTicks do
  begin
    Sleep(1);
    Remaining := ATargetTicks - GetTicks;
  end;
  while GetTicks < ATargetTicks do
    ;
end;

{ TParticleEngine }

constructor TParticleEngine.Create(AParentHandle: HWND; ANumParticles: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FParentHandle := AParentHandle;
  FTargetFPS := 60;
  FActive := False;
  FWidth := 800;
  FHeight := 800;
  FDesiredParticleCount := ANumParticles;
  FParticles := nil;

  // Camera far enough back to see the full (-2..2) scene with room to spare.
  // User can orbit (middle mouse), pan (right mouse) and zoom (wheel).
  FCamera.position := Vector3Create(10.0, 6.0, 10.0);
  FCamera.target := Vector3Create(0, 0.5, 0);
  FCamera.up := Vector3Create(0, 1, 0);
  FCamera.fovy := 45.0;
  FCamera.projection := CAMERA_PERSPECTIVE;

  // Mouse tracking init
  FLastMouseX := 0;
  FLastMouseY := 0;
  FMouseInit := False;

  // Default desired values - cached so a fresh engine (after pool size
  // change) gets the same parameters as the live one.
  FDesiredParticleScale    := 1.0;   // Standard scale
  FDesiredTimeScale        := 1.0;   // real-time
  FDesiredInstancesX1000   := 100.0;  // Render 10% of pool by default (50K of 500K)
  FDesiredBlendMode        := bmAlpha;
  FDesiredGlobalWind       := Vector3Create(0, 0, 0);
  FDesiredGlobalGravity    := Vector3Create(0, 0, 0);  // No global gravity - each preset has its own
  FDesiredHDRMultiplier   := 1.0;
  FDesiredOnEmitterExpired := nil;
end;

destructor TParticleEngine.Destroy;
begin
  StopEngine;
  if Assigned(FParticles) then
    FreeAndNil(FParticles);
  inherited;
end;

procedure TParticleEngine.SetDimensions(const W, H: Integer);
begin
  FWidth := W;
  FHeight := H;
  { Stash the new size in the pending fields and let the engine thread
    perform the actual Raylib SetWindowSize + viewport adjustment. The VCL
    thread CANNOT call SetWindowSize safely: Raylib's window-management
    functions internally resize the GL framebuffer and post window messages,
    which races with BeginDrawing/EndDrawing() running on the engine thread.
    In fullscreen this caused stutter and a mismatched viewport (the engine
    kept rendering at the old small size and Windows stretched it). }
  FPendingWidth := W;
  FPendingHeight := H;
  FPendingResize := True;
  { Still move the HWND now so the user sees the new window shape immediately.
    SetWindowPos does not touch GL state, it just repositions the window in
    the parent. Raylib's internal framebuffer is resized later on the engine
    thread via SetWindowSize. }
  if FRaylibWnd <> 0 then
    SetWindowPos(FRaylibWnd, 0, 0, 0, FWidth, FHeight, SWP_NOZORDER or SWP_NOACTIVATE);
end;

procedure TParticleEngine.SetActive(const Value: Boolean);
begin
  if FActive <> Value then
  begin
    FActive := Value;
    if FActive and Suspended then
      Start;
  end;
end;

procedure TParticleEngine.StartEngine;
begin
  Active := True;
end;

procedure TParticleEngine.StopEngine;
begin
  Active := False;
end;

procedure TParticleEngine.SetFPS(const FPS: Integer);
begin
  if FTargetFPS <> FPS then
    FTargetFPS := FPS;
end;

procedure TParticleEngine.SetCamera(const Pos, Target: TVector3; Fovy: Single);
begin
  FCamera.position := Pos;
  FCamera.target := Target;
  FCamera.fovy := Fovy;
end;

{ ============================================================================
  Global forces forwarders
  ============================================================================ }

procedure TParticleEngine.SetGlobalWind(const AWind: TVector3);
begin
  FDesiredGlobalWind := AWind;
  if Assigned(FParticles) then
    FParticles.SetGlobalWind(AWind);
end;

procedure TParticleEngine.SetGlobalGravity(const AGravity: TVector3);
begin
  FDesiredGlobalGravity := AGravity;
  if Assigned(FParticles) then
    FParticles.SetGlobalGravity(AGravity);
end;

procedure TParticleEngine.SetHDRMultiplier(AMultiplier: Single);
begin
  FDesiredHDRMultiplier := AMultiplier;
  if Assigned(FParticles) then
    FParticles.SetHDRMultiplier(AMultiplier);
end;

procedure TParticleEngine.SetPhysicsBridge(const ABridge: IParticlePhysicsBridge);
begin
  if Assigned(FParticles) then
    FParticles.SetPhysicsBridge(ABridge);
end;

procedure TParticleEngine.SetPhysicsSampleRate(ARate: Integer);
begin
  if Assigned(FParticles) then
    FParticles.SetPhysicsSampleRate(ARate);
end;

procedure TParticleEngine.SetSpriteAtlas(ATextureID: Cardinal);
begin
  if Assigned(FParticles) then
    FParticles.SetSpriteAtlas(ATextureID);
end;

procedure TParticleEngine.ClearSpriteAtlas;
begin
  if Assigned(FParticles) then
    FParticles.ClearSpriteAtlas;
end;

{ ============================================================================
  OnEmitterExpired property forwarders
  ============================================================================ }

function TParticleEngine.GetOnEmitterExpired: TEmitterExpiredEvent;
begin
  if Assigned(FParticles) then
    Result := FParticles.OnEmitterExpired
  else
    Result := nil;
end;

procedure TParticleEngine.SetOnEmitterExpired(AValue: TEmitterExpiredEvent);
begin
  FDesiredOnEmitterExpired := AValue;
  if Assigned(FParticles) then
    FParticles.OnEmitterExpired := AValue;
end;

{ ============================================================================
  Push desired parameter values to the freshly-created engine.
  Called from Execute after FParticles.Initialise succeeds.
  ============================================================================ }

procedure TParticleEngine.PushDesiredValuesToEngine;
begin
  if not Assigned(FParticles) then Exit;
  FParticles.ParticleScale  := FDesiredParticleScale;
  FParticles.TimeScale      := FDesiredTimeScale;
  FParticles.InstancesX1000 := FDesiredInstancesX1000;
  FParticles.SetBlendMode(FDesiredBlendMode);
  FParticles.SetGlobalWind(FDesiredGlobalWind);
  FParticles.SetGlobalGravity(FDesiredGlobalGravity);
  FParticles.SetHDRMultiplier(FDesiredHDRMultiplier);
  if Assigned(FDesiredOnEmitterExpired) then
    FParticles.OnEmitterExpired := FDesiredOnEmitterExpired;
end;

{ ============================================================================
  Camera controls - orbit, pan, zoom using middle/right mouse + wheel.
  ============================================================================ }

{ OrbitCamera rotates the camera position around the target by the given
  yaw (horizontal) and pitch (vertical) deltas in radians. Pitch is clamped
  so the camera never flips over the top. }
procedure TParticleEngine.OrbitCamera(YawDelta, PitchDelta: Single);
var
  Dir: TVector3;
  Radius, Yaw, Pitch: Single;
  NewPos: TVector3;
begin
  Dir.x := FCamera.position.x - FCamera.target.x;
  Dir.y := FCamera.position.y - FCamera.target.y;
  Dir.z := FCamera.position.z - FCamera.target.z;
  Radius := Sqrt(Dir.x*Dir.x + Dir.y*Dir.y + Dir.z*Dir.z);
  if Radius < 0.1 then Exit;
  Dir.x := Dir.x / Radius;
  Dir.y := Dir.y / Radius;
  Dir.z := Dir.z / Radius;
  // Spherical coordinates
  Yaw   := ArcTan2(Dir.x, Dir.z);
  Pitch := ArcSin(Dir.y);
  Yaw   := Yaw + YawDelta;
  Pitch := Pitch + PitchDelta;
  // Clamp pitch to avoid flip
  if Pitch > 1.55 then Pitch := 1.55;
  if Pitch < -1.55 then Pitch := -1.55;
  // Back to cartesian
  NewPos.x := FCamera.target.x + Radius * Cos(Pitch) * Sin(Yaw);
  NewPos.y := FCamera.target.y + Radius * Sin(Pitch);
  NewPos.z := FCamera.target.z + Radius * Cos(Pitch) * Cos(Yaw);
  FCamera.position := NewPos;
end;

{ PanCamera moves both the camera and target by the given delta, projected
  onto the camera's right/up plane. This lets the user drag the ground. }
procedure TParticleEngine.PanCamera(DX, DY: Single);
var
  Fwd, Right, RealUp: TVector3;
  Dist: Single;
begin
  // Forward = target - position
  Fwd.x := FCamera.target.x - FCamera.position.x;
  Fwd.y := FCamera.target.y - FCamera.position.y;
  Fwd.z := FCamera.target.z - FCamera.position.z;
  Dist := Sqrt(Fwd.x*Fwd.x + Fwd.y*Fwd.y + Fwd.z*Fwd.z);
  if Dist > 0.001 then
  begin
    Fwd.x := Fwd.x / Dist;
    Fwd.y := Fwd.y / Dist;
    Fwd.z := Fwd.z / Dist;
  end;
  // Right = cross(Fwd, Up)
  Right.x := Fwd.y * FCamera.up.z - Fwd.z * FCamera.up.y;
  Right.y := Fwd.z * FCamera.up.x - Fwd.x * FCamera.up.z;
  Right.z := Fwd.x * FCamera.up.y - Fwd.y * FCamera.up.x;
  Dist := Sqrt(Right.x*Right.x + Right.y*Right.y + Right.z*Right.z);
  if Dist > 0.001 then
  begin
    Right.x := Right.x / Dist;
    Right.y := Right.y / Dist;
    Right.z := Right.z / Dist;
  end;
  // RealUp = cross(Right, Fwd)
  RealUp.x := Right.y * Fwd.z - Right.z * Fwd.y;
  RealUp.y := Right.z * Fwd.x - Right.x * Fwd.z;
  RealUp.z := Right.x * Fwd.y - Right.y * Fwd.x;
  // Apply pan: DX along Right, DY along RealUp
  FCamera.position.x := FCamera.position.x + Right.x * DX + RealUp.x * DY;
  FCamera.position.y := FCamera.position.y + Right.y * DX + RealUp.y * DY;
  FCamera.position.z := FCamera.position.z + Right.z * DX + RealUp.z * DY;
  FCamera.target.x := FCamera.target.x + Right.x * DX + RealUp.x * DY;
  FCamera.target.y := FCamera.target.y + Right.y * DX + RealUp.y * DY;
  FCamera.target.z := FCamera.target.z + Right.z * DX + RealUp.z * DY;
end;

{ ZoomCamera moves the camera along its forward axis by a fraction of the
  current radius. Wheel > 0 = scroll up = zoom in. }
procedure TParticleEngine.ZoomCamera(WheelDelta: Single);
var
  Dir: TVector3;
  Radius, NewRadius: Single;
begin
  Dir.x := FCamera.position.x - FCamera.target.x;
  Dir.y := FCamera.position.y - FCamera.target.y;
  Dir.z := FCamera.position.z - FCamera.target.z;
  Radius := Sqrt(Dir.x*Dir.x + Dir.y*Dir.y + Dir.z*Dir.z);
  if Radius < 0.1 then Exit;
  NewRadius := Radius - WheelDelta * Radius * 0.15;
  if NewRadius < 0.5 then NewRadius := 0.5;
  if NewRadius > 200.0 then NewRadius := 200.0;
  Dir.x := Dir.x * (NewRadius / Radius);
  Dir.y := Dir.y * (NewRadius / Radius);
  Dir.z := Dir.z * (NewRadius / Radius);
  FCamera.position.x := FCamera.target.x + Dir.x;
  FCamera.position.y := FCamera.target.y + Dir.y;
  FCamera.position.z := FCamera.target.z + Dir.z;
end;

{ ============================================================================
  Mouse handling - camera controls + particle push.
  Left mouse   = push particles away from cursor
  Middle mouse = orbit camera around target
  Right mouse  = pan camera + target (drag ground)
  Mouse wheel  = zoom in/out
  ============================================================================ }

procedure TParticleEngine.CheckMousePush;
var
  MX, MY, MDX, MDY, SW, SH: Integer;
  Wheel: Single;
  Eye, Target, Up, Fwd, Right, RealUp: TVector3;
  NdcX, NdcY, Dist, TanFovy, Aspect: Single;
  PushPos: TVector3;
  IsActive: Boolean;
begin
  if not Assigned(FParticles) then Exit;

  // === Camera controls (always read mouse, independent of push) ===
  MX := GetMouseX;
  MY := GetMouseY;
  if not FMouseInit then
  begin
    FLastMouseX := MX;
    FLastMouseY := MY;
    FMouseInit := True;
  end;
  MDX := MX - FLastMouseX;
  MDY := MY - FLastMouseY;
  FLastMouseX := MX;
  FLastMouseY := MY;

  // Middle mouse = orbit around target
  if IsMouseButtonDown(MOUSE_MIDDLE_BUTTON) then
  begin
    OrbitCamera(Single(MDX) * 0.01, -Single(MDY) * 0.01);
  end
  // Right mouse = pan target+camera
  else if IsMouseButtonDown(MOUSE_RIGHT_BUTTON) then
  begin
    PanCamera(-Single(MDX) * 0.02, Single(MDY) * 0.02);
  end;

  // Mouse wheel = zoom
  Wheel := GetMouseWheelMove();
  if Abs(Wheel) > 0.001 then
    ZoomCamera(Wheel);

  // === Particle push (left mouse, only when engine is active) ===
  IsActive := FActive;
  if IsActive and IsMouseButtonDown(MOUSE_LEFT_BUTTON) then
  begin
    SW := FWidth;
    SH := FHeight;
    if SW <= 0 then SW := 1;
    if SH <= 0 then SH := 1;

    Eye := FCamera.position;
    Target := FCamera.target;
    Up := FCamera.up;

    // Forward = normalize(Target - Eye)
    Fwd.x := Target.x - Eye.x;
    Fwd.y := Target.y - Eye.y;
    Fwd.z := Target.z - Eye.z;
    Dist := Sqrt(Fwd.x*Fwd.x + Fwd.y*Fwd.y + Fwd.z*Fwd.z);
    if Dist > 0.001 then
    begin
      Fwd.x := Fwd.x / Dist; Fwd.y := Fwd.y / Dist; Fwd.z := Fwd.z / Dist;
    end;

    // Right = normalize(cross(Fwd, Up))
    Right.x := Fwd.y * Up.z - Fwd.z * Up.y;
    Right.y := Fwd.z * Up.x - Fwd.x * Up.z;
    Right.z := Fwd.x * Up.y - Fwd.y * Up.x;
    Dist := Sqrt(Right.x*Right.x + Right.y*Right.y + Right.z*Right.z);
    if Dist > 0.001 then
    begin
      Right.x := Right.x / Dist; Right.y := Right.y / Dist; Right.z := Right.z / Dist;
    end;

    // RealUp = cross(Right, Fwd)
    RealUp.x := Right.y * Fwd.z - Right.z * Fwd.y;
    RealUp.y := Right.z * Fwd.x - Right.x * Fwd.z;
    RealUp.z := Right.x * Fwd.y - Right.y * Fwd.x;

    Dist := Sqrt(Sqr(Eye.x - Target.x) + Sqr(Eye.y - Target.y) + Sqr(Eye.z - Target.z));
    NdcX := (2.0 * MX / SW) - 1.0;
    NdcY := 1.0 - (2.0 * MY / SH);
    TanFovy := System.Math.Tan(FCamera.fovy * 0.5 * Pi / 180.0);
    Aspect := SW / SH;

    PushPos.x := Eye.x + Fwd.x * Dist + Right.x * NdcX * TanFovy * Aspect * Dist
                 + RealUp.x * NdcY * TanFovy * Dist;
    PushPos.y := Eye.y + Fwd.y * Dist + Right.y * NdcX * TanFovy * Aspect * Dist
                 + RealUp.y * NdcY * TanFovy * Dist;
    PushPos.z := Eye.z + Fwd.z * Dist + Right.z * NdcX * TanFovy * Aspect * Dist
                 + RealUp.z * NdcY * TanFovy * Dist;

    FParticles.SetPush(PushPos, 0.3, 8.0);
  end
  else
  begin
    if FActive then
      FParticles.ClearPush;
  end;
end;

{ ============================================================================
  Simulation control
  ============================================================================ }

procedure TParticleEngine.Restart;
begin
  if Assigned(FParticles) then
    FParticles.Restart;
end;

procedure TParticleEngine.Reset;
begin
  // Reset the in-engine params AND the FDesired* fields (so a future
  // engine recreation uses the defaults too).
  FDesiredParticleScale    := 1.0;
  FDesiredTimeScale        := 1.0;
  FDesiredInstancesX1000   := 100.0;
  FDesiredBlendMode        := bmAlpha;
  FDesiredGlobalWind       := Vector3Create(0, 0, 0);
  FDesiredGlobalGravity    := Vector3Create(0, 0, 0);
  FDesiredHDRMultiplier   := 1.0;
  if Assigned(FParticles) then
    FParticles.Reset;
end;

{ ============================================================================
  Parameter setters - store desired value AND push to live engine if ready.
  ============================================================================ }

procedure TParticleEngine.SetParticleScale(Value: Single);
begin
  FDesiredParticleScale := Value;
  if Assigned(FParticles) then
    FParticles.ParticleScale := Value;
end;

procedure TParticleEngine.SetTimeScale(Value: Single);
begin
  FDesiredTimeScale := Value;
  if Assigned(FParticles) then
    FParticles.TimeScale := Value;
end;

procedure TParticleEngine.SetInstancesX1000(Value: Single);
begin
  FDesiredInstancesX1000 := Value;
  if Assigned(FParticles) then
    FParticles.InstancesX1000 := Value;
end;

procedure TParticleEngine.SetBlendMode(Value: TYutaniBlendMode);
begin
  FDesiredBlendMode := Value;
  if Assigned(FParticles) then
    FParticles.SetBlendMode(Value);
end;

{ ============================================================================
  Generic Emitter API - straight pass-through to the GPU engine. Safe to
  call from any thread; the engine itself locks internally.
  ============================================================================ }

function TParticleEngine.AddEmitter(const AData: TYutaniEmitterData): Integer;
begin
  if not Assigned(FParticles) then
  begin
    Result := -1;
    Exit;
  end;
  Result := FParticles.AddEmitter(AData);
end;

function TParticleEngine.RemoveEmitter(EmitterID: Integer): Boolean;
begin
  if not Assigned(FParticles) then
  begin
    Result := False;
    Exit;
  end;
  Result := FParticles.RemoveEmitter(EmitterID);
end;

procedure TParticleEngine.ClearEmitters;
begin
  if Assigned(FParticles) then
    FParticles.ClearEmitters;
end;

function TParticleEngine.GetEmitterCount: Integer;
begin
  if not Assigned(FParticles) then
  begin
    Result := 0;
    Exit;
  end;
  Result := FParticles.NumEmitters;
end;

function TParticleEngine.GetEmitter(EmitterID: Integer;
  out AEmitter: TYutaniEmitterData): Boolean;
begin
  if not Assigned(FParticles) then
  begin
    AEmitter := MakeEmitterData;
    Result := False;
    Exit;
  end;
  Result := FParticles.GetEmitter(EmitterID, AEmitter);
end;

function TParticleEngine.SetEmitterActive(EmitterID: Integer;
  AActive: Boolean): Boolean;
begin
  if not Assigned(FParticles) then
  begin
    Result := False;
    Exit;
  end;
  Result := FParticles.SetEmitterActive(EmitterID, AActive);
end;

function TParticleEngine.SetEmitterStartColor(EmitterID: Integer;
  const AColor: TColorB): Boolean;
begin
  if not Assigned(FParticles) then
  begin
    Result := False;
    Exit;
  end;
  Result := FParticles.SetEmitterStartColor(EmitterID, AColor);
end;

function TParticleEngine.SetEmitterEndColor(EmitterID: Integer;
  const AColor: TColorB): Boolean;
begin
  if not Assigned(FParticles) then
  begin
    Result := False;
    Exit;
  end;
  Result := FParticles.SetEmitterEndColor(EmitterID, AColor);
end;

function TParticleEngine.SetEmitterGlow(EmitterID: Integer;
  AGlow: Single): Boolean;
begin
  if not Assigned(FParticles) then
  begin
    Result := False;
    Exit;
  end;
  Result := FParticles.SetEmitterGlow(EmitterID, AGlow);
end;

function TParticleEngine.SetEmitterTrailStrength(EmitterID: Integer;
  AStrength: Single): Boolean;
begin
  if not Assigned(FParticles) then
  begin
    Result := False;
    Exit;
  end;
  Result := FParticles.SetEmitterTrailStrength(EmitterID, AStrength);
end;

function TParticleEngine.SetEmitterUseColorOverride(EmitterID: Integer;
  AUse: Boolean): Boolean;
begin
  if not Assigned(FParticles) then
  begin
    Result := False;
    Exit;
  end;
  Result := FParticles.SetEmitterUseColorOverride(EmitterID, AUse);
end;

function TParticleEngine.SetEmitterLifeMode(EmitterID: Integer;
  AMode: TYutaniLifeMode): Boolean;
begin
  if not Assigned(FParticles) then
  begin
    Result := False;
    Exit;
  end;
  Result := FParticles.SetEmitterLifeMode(EmitterID, AMode);
end;

function TParticleEngine.SetEmitterRegion(EmitterID: Integer;
  const ARegionMin, ARegionMax: TVector3): Boolean;
begin
  if not Assigned(FParticles) then
  begin
    Result := False;
    Exit;
  end;
  Result := FParticles.SetEmitterRegion(EmitterID, ARegionMin, ARegionMax);
end;

function TParticleEngine.SetEmitterOrigin(EmitterID: Integer;
  const AOrigin: TVector3): Boolean;
begin
  if not Assigned(FParticles) then
  begin
    Result := False;
    Exit;
  end;
  Result := FParticles.SetEmitterOrigin(EmitterID, AOrigin);
end;

function TParticleEngine.SetEmitterFromTo(EmitterID: Integer;
  const AFromPos, AToPos: TVector3): Boolean;
begin
  if not Assigned(FParticles) then
  begin
    Result := False;
    Exit;
  end;
  Result := FParticles.SetEmitterFromTo(EmitterID, AFromPos, AToPos);
end;

{ ============================================================================
  Materialize / Dematerialize presets
  ============================================================================ }

procedure TParticleEngine.EmitMaterializeCube(const TargetPos: TVector3;
  VoxelSize: Single);
begin
  if Assigned(FParticles) then
    FParticles.EmitMaterializeCube(TargetPos, VoxelSize);
end;

procedure TParticleEngine.EmitDematerializeCube(const SourcePos: TVector3;
  VoxelSize: Single);
begin
  if Assigned(FParticles) then
    FParticles.EmitDematerializeCube(SourcePos, VoxelSize);
end;

procedure TParticleEngine.EmitMaterializeMesh(const TargetPos: TVector3;
  const Mesh: TMesh);
begin
  if Assigned(FParticles) then
    FParticles.EmitMaterializeMesh(TargetPos, Mesh);
end;

procedure TParticleEngine.EmitDematerializeMesh(const SourcePos: TVector3;
  const Mesh: TMesh);
begin
  if Assigned(FParticles) then
    FParticles.EmitDematerializeMesh(SourcePos, Mesh);
end;

{ ============================================================================
  PRESET EMITTER FACTORIES
  Each factory builds a TYutaniEmitterData with the right modular parameters
  for a classic effect and calls AddEmitter.
  ============================================================================ }

function TParticleEngine.CreateFireEmitter(const AOrigin: TVector3;
  ARadius: Single; AParticleCount: Integer): Integer;
var
  D: TYutaniEmitterData;
begin
  D := MakeEmitterData;
  D.SpawnShape := ssSphere;
  D.Origin := AOrigin;
  D.SpawnDir := Vector3Create(0, 1, 0);
  D.SpawnRadius := ARadius;
  D.MinSpeed := 0.3;
  D.MaxSpeed := 1.0;
  D.MinLife := 1.0;
  D.MaxLife := 2.0;
  D.StartSize := 0.20;
  D.EndSize := 0.06;
  // Saturated orange -> deep red. Low glow so color does NOT clip to white.
  D.StartColor := MakeCol(255, 140, 30, 255);
  D.EndColor   := MakeCol(120, 20, 0, 0);
  D.UseColorOverride := True;
  D.Glow := 0.2;            // +20% brightness, keeps orange visible
  D.TrailStrength := 0.4;
  D.Gravity := Vector3Create(0, 3.0, 0);  // hot air rises
  D.Drag := 0.3;
  D.CurlNoiseStrength := 3.0;  // turbulent flicker
  D.CurlNoiseFreq := 2.0;
  D.LifeMode := lmOneShotAutoRemove;
  D.BlendMode := bmAdditive;
  D.TextureIndex := -1;
  D.ParticleCount := AParticleCount;
  D.Name := 'Fire';
  Result := AddEmitter(D);
end;

function TParticleEngine.CreateExplosionEmitter(const AOrigin: TVector3;
  ARadius: Single; AParticleCount: Integer): Integer;
var
  D: TYutaniEmitterData;
begin
  D := MakeEmitterData;
  D.SpawnShape := ssSphere;
  D.Origin := AOrigin;
  D.SpawnDir := Vector3Create(0, 1, 0);
  D.SpawnRadius := ARadius * 0.2;
  D.MinSpeed := 5.0;
  D.MaxSpeed := 10.0;
  D.MinLife := 1.0;
  D.MaxLife := 2.0;
  D.StartSize := 0.25;
  D.EndSize := 0.06;
  // Bright orange flash -> dark smoke fade
  D.StartColor := MakeCol(255, 180, 60, 255);
  D.EndColor   := MakeCol(60, 20, 10, 0);
  D.UseColorOverride := True;
  D.Glow := 0.3;
  D.TrailStrength := 0.6;
  D.Gravity := Vector3Create(0, -3.0, 0);  // debris falls back
  D.Drag := 0.6;
  D.CurlNoiseStrength := 1.0;
  D.CurlNoiseFreq := 1.5;
  D.LifeMode := lmOneShotAutoRemove;
  D.BlendMode := bmAdditive;
  D.TextureIndex := -1;
  D.ParticleCount := AParticleCount;
  D.Name := 'Explosion';
  Result := AddEmitter(D);
end;

function TParticleEngine.CreateSmokeEmitter(const AOrigin: TVector3;
  ARadius: Single; AParticleCount: Integer): Integer;
var
  D: TYutaniEmitterData;
begin
  D := MakeEmitterData;
  D.SpawnShape := ssSphere;
  D.Origin := AOrigin;
  D.SpawnDir := Vector3Create(0, 1, 0);
  D.SpawnRadius := ARadius;
  D.MinSpeed := 0.2;
  D.MaxSpeed := 0.5;
  D.MinLife := 3.0;
  D.MaxLife := 5.0;
  D.StartSize := 0.15;
  D.EndSize := 0.50;  // big expanding puffs
  // Dark gray -> nearly transparent
  D.StartColor := MakeCol(120, 120, 120, 200);
  D.EndColor   := MakeCol(50, 50, 50, 0);
  D.UseColorOverride := True;
  D.Glow := 0;
  D.TrailStrength := 0;
  D.Gravity := Vector3Create(0, 1.5, 0);  // smoke rises gently
  D.Drag := 0.2;
  D.CurlNoiseStrength := 2.0;
  D.CurlNoiseFreq := 0.7;
  D.LifeMode := lmOneShotAutoRemove;
  D.BlendMode := bmAlpha;
  D.TextureIndex := -1;
  D.ParticleCount := AParticleCount;
  D.Name := 'Smoke';
  Result := AddEmitter(D);
end;

function TParticleEngine.CreateSparksEmitter(const AOrigin: TVector3;
  ARadius: Single; AParticleCount: Integer): Integer;
var
  D: TYutaniEmitterData;
begin
  D := MakeEmitterData;
  D.SpawnShape := ssSphere;
  D.Origin := AOrigin;
  D.SpawnDir := Vector3Create(0, 1, 0);
  D.SpawnRadius := ARadius * 0.1;
  D.MinSpeed := 4.0;
  D.MaxSpeed := 8.0;
  D.MinLife := 0.6;
  D.MaxLife := 1.5;
  D.StartSize := 0.08;
  D.EndSize := 0.03;
  // Bright yellow-orange -> dark red fade
  D.StartColor := MakeCol(255, 200, 80, 255);
  D.EndColor   := MakeCol(200, 60, 10, 0);
  D.UseColorOverride := True;
  D.Glow := 0.4;
  D.TrailStrength := 1.5;  // long streaks
  D.Gravity := Vector3Create(0, -9.81, 0);  // sparks fall
  D.Drag := 0.1;
  D.CurlNoiseStrength := 0.3;
  D.CurlNoiseFreq := 3.0;
  D.LifeMode := lmOneShotAutoRemove;
  D.BlendMode := bmAdditive;
  D.TextureIndex := -1;
  D.ParticleCount := AParticleCount;
  D.Name := 'Sparks';
  Result := AddEmitter(D);
end;

function TParticleEngine.CreateRainEmitter(const ARegionMin, ARegionMax: TVector3;
  AParticleCount: Integer): Integer;
var
  D: TYutaniEmitterData;
begin
  D := MakeEmitterData;
  D.SpawnShape := ssBox;
  D.Origin := Vector3Create((ARegionMin.x + ARegionMax.x) * 0.5,
                            (ARegionMin.y + ARegionMax.y) * 0.5,
                            (ARegionMin.z + ARegionMax.z) * 0.5);
  D.RegionMin := ARegionMin;
  D.RegionMax := ARegionMax;
  D.MinSpeed := 0;
  D.MaxSpeed := 0;
  D.MinLife := 2.0;
  D.MaxLife := 3.0;
  D.StartSize := 0.08;
  D.EndSize := 0.08;
  // Clear blue raindrops
  D.StartColor := MakeCol(80, 140, 220, 200);
  D.EndColor   := MakeCol(80, 140, 220, 200);
  D.UseColorOverride := False;
  D.Glow := 0;
  D.TrailStrength := 1.5;  // long streaks for rain look
  D.Gravity := Vector3Create(0, -15.0, 0);  // rain falls fast
  D.Drag := 0;
  D.FloorY := ARegionMin.y;
  D.Bounce := 0;
  D.LifeMode := lmOneShotAutoRemove;
  D.BlendMode := bmAlpha;
  D.TextureIndex := -1;
  D.ParticleCount := AParticleCount;
  D.Name := 'Rain';
  Result := AddEmitter(D);
end;

function TParticleEngine.CreateSnowEmitter(const ARegionMin, ARegionMax: TVector3;
  AParticleCount: Integer): Integer;
var
  D: TYutaniEmitterData;
begin
  D := MakeEmitterData;
  D.SpawnShape := ssBox;
  D.Origin := Vector3Create((ARegionMin.x + ARegionMax.x) * 0.5,
                            (ARegionMin.y + ARegionMax.y) * 0.5,
                            (ARegionMin.z + ARegionMax.z) * 0.5);
  D.RegionMin := ARegionMin;
  D.RegionMax := ARegionMax;
  D.MinSpeed := 0;
  D.MaxSpeed := 0;
  D.MinLife := 5.0;
  D.MaxLife := 8.0;
  D.StartSize := 0.10;
  D.EndSize := 0.10;
  D.StartColor := MakeCol(255, 255, 255, 230);
  D.EndColor   := MakeCol(255, 255, 255, 230);
  D.UseColorOverride := False;
  D.Glow := 0;
  D.TrailStrength := 0;
  D.Gravity := Vector3Create(0, -0.8, 0);  // snow drifts down slowly
  D.Drag := 0;
  D.CurlNoiseStrength := 0.8;
  D.CurlNoiseFreq := 0.3;  // slow sway
  D.FloorY := ARegionMin.y;
  D.Bounce := 0;
  D.LifeMode := lmOneShotAutoRemove;
  D.BlendMode := bmAlpha;
  D.TextureIndex := -1;
  D.ParticleCount := AParticleCount;
  D.Name := 'Snow';
  Result := AddEmitter(D);
end;

function TParticleEngine.CreateMagicEmitter(const AOrigin: TVector3;
  ARadius: Single; AParticleCount: Integer): Integer;
var
  D: TYutaniEmitterData;
begin
  D := MakeEmitterData;
  D.SpawnShape := ssSphere;
  D.Origin := AOrigin;
  D.SpawnDir := Vector3Create(0, 1, 0);
  D.SpawnRadius := ARadius;
  D.MinSpeed := 0.5;
  D.MaxSpeed := 1.5;
  D.MinLife := 2.5;
  D.MaxLife := 4.5;
  D.StartSize := 0.12;
  D.EndSize := 0.05;
  // Purple -> cyan sparkle
  D.StartColor := MakeCol(160, 80, 255, 230);
  D.EndColor   := MakeCol(60, 180, 255, 0);
  D.UseColorOverride := True;
  D.Glow := 0.3;
  D.TrailStrength := 0.5;
  D.Gravity := Vector3Create(0, 0, 0);  // magic floats
  D.Drag := 0.3;
  D.CurlNoiseStrength := 2.5;
  D.CurlNoiseFreq := 1.0;
  D.VortexStrength := 3.0;
  D.RadialForce := 0.5;  // gentle pull to origin
  D.LifeMode := lmOneShotAutoRemove;
  D.BlendMode := bmAdditive;
  D.TextureIndex := -1;
  D.ParticleCount := AParticleCount;
  D.Name := 'Magic';
  Result := AddEmitter(D);
end;

function TParticleEngine.CreateVortexEmitter(const AOrigin, AAxis: TVector3;
  ARadius: Single; AParticleCount: Integer): Integer;
var
  D: TYutaniEmitterData;
begin
  D := MakeEmitterData;
  D.SpawnShape := ssSphere;
  D.Origin := AOrigin;
  D.SpawnDir := AAxis;
  if Vector3Length(D.SpawnDir) < 0.001 then
    D.SpawnDir := Vector3Create(0, 1, 0)
  else
    D.SpawnDir := Vector3Normalize(D.SpawnDir);
  D.SpawnRadius := ARadius;
  D.MinSpeed := 0.5;
  D.MaxSpeed := 1.5;
  D.MinLife := 3.0;
  D.MaxLife := 5.0;
  D.StartSize := 0.08;
  D.EndSize := 0.08;
  // Light blue-gray swirling particles
  D.StartColor := MakeCol(180, 200, 230, 200);
  D.EndColor   := MakeCol(140, 160, 200, 100);
  D.UseColorOverride := True;
  D.Glow := 0.2;
  D.TrailStrength := 0.8;
  D.Gravity := Vector3Create(0, 0.5, 0);  // slight upward drift
  D.Drag := 0.05;
  D.CurlNoiseStrength := 0.3;
  D.CurlNoiseFreq := 1.0;
  D.VortexStrength := 5.0;  // strong rotation
  D.RadialForce := -0.5;   // push outward so it forms a visible funnel
  D.LifeMode := lmOneShotAutoRemove;
  D.BlendMode := bmAlpha;
  D.TextureIndex := -1;
  D.ParticleCount := AParticleCount;
  D.Name := 'Vortex';
  Result := AddEmitter(D);
end;

function TParticleEngine.CreateFountainEmitter(const AOrigin: TVector3;
  AParticleCount: Integer): Integer;
var
  D: TYutaniEmitterData;
begin
  D := MakeEmitterData;
  D.SpawnShape := ssCone;
  D.Origin := AOrigin;
  D.SpawnDir := Vector3Create(0, 1, 0);  // straight up
  D.SpawnRadius := 0.4;  // cone half-angle ~23 degrees
  D.MinSpeed := 5.0;
  D.MaxSpeed := 8.0;
  D.Spread := 0.3;
  D.MinLife := 2.0;
  D.MaxLife := 3.5;
  D.StartSize := 0.12;
  D.EndSize := 0.05;
  // Bright blue water -> transparent
  D.StartColor := MakeCol(80, 160, 255, 220);
  D.EndColor   := MakeCol(40, 100, 200, 0);
  D.UseColorOverride := True;
  D.Glow := 0.1;
  D.TrailStrength := 0.8;
  D.Gravity := Vector3Create(0, -9.81, 0);  // water arcs back down
  D.Drag := 0.05;
  D.FloorY := AOrigin.y - 0.1;
  D.Bounce := 0.3;  // splash bounce
  D.LifeMode := lmOneShotAutoRemove;
  D.BlendMode := bmAlpha;
  D.TextureIndex := -1;
  D.ParticleCount := AParticleCount;
  D.Name := 'Fountain';
  Result := AddEmitter(D);
end;

function TParticleEngine.CreateThrusterEmitter(const AOrigin, ADirection: TVector3;
  AConeAngle: Single; AParticleCount: Integer): Integer;
var
  D: TYutaniEmitterData;
begin
  D := MakeEmitterData;
  D.SpawnShape := ssCone;
  D.Origin := AOrigin;
  if Vector3Length(ADirection) > 0.001 then
    D.SpawnDir := Vector3Normalize(ADirection)
  else
    D.SpawnDir := Vector3Create(0, 0, 1);
  D.SpawnRadius := AConeAngle;
  D.MinSpeed := 4.0;
  D.MaxSpeed := 7.0;
  D.Spread := 0.3;
  D.MinLife := 0.8;
  D.MaxLife := 1.5;
  D.StartSize := 0.15;
  D.EndSize := 0.05;
  // Blue-hot core -> orange -> dark smoke
  D.StartColor := MakeCol(150, 200, 255, 255);
  D.EndColor   := MakeCol(60, 60, 60, 0);
  D.UseColorOverride := True;
  D.Glow := 0.3;
  D.TrailStrength := 1.0;
  D.Gravity := Vector3Create(0, 0, 0);  // thruster goes straight
  D.Drag := 0.3;
  D.CurlNoiseStrength := 1.0;
  D.CurlNoiseFreq := 2.0;
  D.LifeMode := lmOneShotAutoRemove;
  D.BlendMode := bmAdditive;
  D.TextureIndex := -1;
  D.ParticleCount := AParticleCount;
  D.Name := 'Thruster';
  Result := AddEmitter(D);
end;

{ ============================================================================
  Render scene - draws the particle engine inside the Raylib window.
  Note: DrawText works fine after the particle pass because the engine now
  properly restores Raylib's rlgl state cache (see DrawInstances in the GPU
  unit). }
{ ============================================================================ }

procedure TParticleEngine.RenderScene;
begin
  BeginDrawing();
  ClearBackground(BLACK);  // Solid black clear - fixes the "particles stick to lens after Clear" bug

  // Camera is manually controlled by the user via middle-mouse orbit,
  // right-mouse pan and wheel zoom. See CheckMousePush for details.

  rlEnableDepthTest();
  rlDisableBackfaceCulling();
  BeginMode3D(FCamera);
  try
    DrawCubeWires(Vector3Create(0, 0, 0), 1.0, 1.0, 1.0, DARKGRAY);
    DrawGrid(20, 1.0);
    if Assigned(FParticles) then
      FParticles.Render(FCamera);
  finally
    EndMode3D();
  end;

  rlEnableBackfaceCulling();
  rlDisableDepthTest();

  // No in-window HUD - the user wants it gone. Status (FPS, emitter count,
  // pool size) is shown in the VCL form's labels instead.

  EndDrawing();

  { Asynchronous invalidation of the Raylib child HWND inside the VCL parent
    panel. We MUST invalidate the parent so the embedded child window's
    freshly-swapped back buffer becomes visible, but we deliberately do NOT
    pass RDW_UPDATENOW here - that flag forces a synchronous WM_PAINT in the
    VCL thread every frame, which in fullscreen (where the parent panel is
    the entire screen) blocks the engine thread for several ms per frame and
    is the #1 cause of fullscreen stutter. RDW_INVALIDATE alone just marks
    the region dirty; Windows repaints it on the VCL thread's own time-slice
    without blocking us. The Raylib back-buffer has already been swapped by
    EndDrawing() above, so the visible content is already current. }
  if FRaylibWnd <> 0 then
    RedrawWindow(FRaylibWnd, nil, 0, RDW_INVALIDATE);
end;

procedure TParticleEngine.Execute;
var
  Timer: THighResTimer;
  Freq, FrameTicks: Int64;
  NextFrame, NowTicks, LastFrameTicks: Int64;
  DeltaSec: Double;
  FrameCount: Integer;
  LastFpsTime: Int64;
  WindowName: AnsiString;
begin
  {$IFDEF MSWINDOWS}
  timeBeginPeriod(1);
  {$ENDIF}
  try
    { Window flags: VSYNC_HINT lets the driver synchronize EndDrawing() to
      the monitor refresh instead of letting the timer spin between frames.
      We no longer request FLAG_MSAA_4X_HINT: with 500K particles filling the
      screen, MSAA 4x multiplied the pixel-shading cost ~4x and was the
      dominant cost in fullscreen. The particle billboards are circular
      quads with soft edges - MSAA gives essentially no visual benefit but
      kills performance. The compute-shader particle sim is unaffected. }
    SetConfigFlags(FLAG_VSYNC_HINT);
    WindowName := AnsiString('ParticleEngine_' + IntToStr(IntPtr(Self)));
    InitWindow(FWidth, FHeight, PAnsiChar(WindowName));

    { Tell Raylib to target 60 FPS explicitly. With VSYNC_HINT set above, the
      actual frame rate is capped by the monitor refresh; SetTargetFPS still
      matters because Raylib uses it as the wait-time budget when the driver
      VSync is in windowed mode. }
    SetTargetFPS(60);

    FRaylibWnd := FindWindowA(nil, PAnsiChar(WindowName));
    if (FRaylibWnd <> 0) and (FParentHandle <> 0) then
    begin
      Winapi.Windows.SetParent(FRaylibWnd, FParentHandle);
      SetWindowLong(FRaylibWnd, GWL_STYLE, WS_CHILD or WS_VISIBLE);
      SetWindowPos(FRaylibWnd, 0, 0, 0, FWidth, FHeight, SWP_NOZORDER or SWP_NOACTIVATE);
    end;

    // Create + initialise the compute-shader particle engine HERE.
    FParticles := TYutaniParticleEngine.Create(FDesiredParticleCount);
    FParticles.Initialise;

    // Push the currently-desired parameter values to the fresh engine.
    PushDesiredValuesToEngine;

    // No auto-spawn at startup - the user wants a clean scene to spawn
    // emitters manually via the preset buttons.

    // Initialize frame pacing timers
    Timer.Init;
    Freq := Timer.Frequency;
    if Freq <= 0 then Freq := 10000000;
    NowTicks := Timer.GetTicks;
    LastFrameTicks := NowTicks;
    NextFrame := NowTicks;
    LastFpsTime := NowTicks;
    FrameCount := 0;
    FPendingResize := False;  // initial size already applied by InitWindow

    while not Terminated do
    begin
      if WindowShouldClose() then Break;

      { Apply any pending window resize that the VCL thread requested via
        SetDimensions. Doing this on the engine thread (not the VCL thread)
        is mandatory: SetWindowSize touches Raylib's internal framebuffer
        and posts WM_SIZE/WM_PAINT, which race with Begin/EndDrawing on
        this thread. We also explicitly call rlViewport so the GL viewport
        matches the new framebuffer size - Raylib's SetWindowSize normally
        handles this, but when the HWND is embedded as a child of a VCL
        panel Raylib sometimes misses the WM_SIZE message. }
      if FPendingResize then
      begin
        FPendingResize := False;
        SetWindowSize(FPendingWidth, FPendingHeight);
        FWidth := FPendingWidth;
        FHeight := FPendingHeight;
      end;

      NowTicks := Timer.GetTicks;
      DeltaSec := (NowTicks - LastFrameTicks) / Freq;
      LastFrameTicks := NowTicks;

      if (DeltaSec <= 0) or (DeltaSec > 0.25) then
        DeltaSec := 1 / 60;

      // Always check mouse for camera controls, even when not active.
      CheckMousePush;
      // Always update the simulation - we want particles to be visible
      // and animated even on startup, not just after the user clicks Start.
      if Assigned(FParticles) then
        FParticles.Update(DeltaSec);
      RenderScene;

      Inc(FrameCount);
      if (NowTicks - LastFpsTime) >= Freq then
      begin
        FRealFPS := Round(FrameCount * Freq / (NowTicks - LastFpsTime));
        FrameCount := 0;
        LastFpsTime := NowTicks;
      end;

      if FTargetFPS > 0 then
        FrameTicks := Round(Freq / FTargetFPS)
      else
        FrameTicks := Freq div 60;
      NextFrame := NextFrame + FrameTicks;

      NowTicks := Timer.GetTicks;
      if (NowTicks - NextFrame) > Freq then
        NextFrame := NowTicks;

      Timer.HybridWaitUntil(NextFrame, SPIN_THRESHOLD_NS);
    end;
  finally
    FreeAndNil(FParticles);
    if FRaylibWnd <> 0 then
      CloseWindow();
    {$IFDEF MSWINDOWS}
    timeEndPeriod(1);
    {$ENDIF}
  end;
end;

end.
