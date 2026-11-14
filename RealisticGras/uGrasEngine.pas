{*******************************************************************************
  GrasEngine Demo Wrapper
********************************************************************************
  Threaded VCL Raylib wrapper for the Yutani.Render.Gras GPU grass engine.

  This is the grass equivalent of uParticleEngine.pas: it owns the Raylib
  render window (embedded as a child of a VCL panel), owns the
  TYutaniGrassEngine, drives the compute + render loop on a worker thread
  and exposes the grass configuration (field position, field size, blade
  size, wind, grass colors) through simple setters that the VCL form
  calls from its slider/button handlers.

  Differences from uParticleEngine.pas:
    - No mode switching, no emitter spawning - grass only.
    - No mouse push interaction - grass does not react to clicks.
    - No Lorenz/sigma/rho/beta/instancesX1000 controls - irrelevant for grass.
    - Camera defaults are tuned for a 20x20 ground patch instead of the
      (-1,1) particle demo volume.

  Author: Lara Miriam Tamy Reschke / LamitaOne
*******************************************************************************}

unit uGrasEngine;

interface

uses
  System.SysUtils, System.Types, System.Classes, System.Math, System.SyncObjs,
  Winapi.Windows, Winapi.MMSystem, Vcl.Controls, Raylib, rlgl, RayMath,
  Yutani.Render.Gras;

const
  SPIN_THRESHOLD_NS = 2000000;
  DEFAULT_BLADE_COUNT = 500000;  // 500K default - fluid on iGPUs (Ryzen 4500U / Vega 6) and already fully dense on a 20x20 patch. The user can crank this to 1M / 2M via the form's Blade Count combo.

type
  THighResTimer = record
    Frequency: Int64;
    procedure Init;
    function GetTicks: Int64; inline;
    procedure HybridWaitUntil(const ATargetTicks, ASpinNanoseconds: Int64);
  end;

  TGrasEngine = class(TThread)
  private
    FParentHandle: HWND;
    FRaylibWnd: HWND;
    FTargetFPS: Integer;
    FRealFPS: Integer;
    FActive: Boolean;
    FWidth, FHeight: Integer;
    FGrass: TYutaniGrassEngine;
    FCamera: TCamera3D;
    FAutoRotate: Boolean;
    FCamYaw: Single;
    FCamPitch: Single;
    FCamDist: Single;
    { Desired parameter values - stored independently of FGrass so that
      when the engine is recreated (e.g. after the user picked a new pool
      size), the current slider values can be pushed to the fresh engine. }
    FDesiredFieldOriginX: Single;
    FDesiredFieldOriginY: Single;
    FDesiredFieldOriginZ: Single;
    FDesiredFieldWidth:   Single;
    FDesiredFieldDepth:   Single;
    FDesiredBladeHeight:  Single;
    FDesiredBladeWidth:   Single;
    FDesiredWindDirX:     Single;
    FDesiredWindDirY:     Single;
    FDesiredWindDirZ:     Single;
    FDesiredWindStrength: Single;
    FDesiredWindGustFreq: Single;
    FDesiredGrassBaseR:   Single;
    FDesiredGrassBaseG:   Single;
    FDesiredGrassBaseB:   Single;
    FDesiredGrassTipR:    Single;
    FDesiredGrassTipG:    Single;
    FDesiredGrassTipB:    Single;
    FDesiredColorVariation: Single;
    FDesiredHDRMultiplier:  Single;
    FDesiredParticleScale:  Single;
    FDesiredBendAmount:     Single;
    // Mouse push - tuned from the form's Push Radius / Push Strength sliders.
    FDesiredPushRadius:     Single;
    FDesiredPushStrength:   Single;
    // True after UpdateCameraOnce has been called this frame. Reset to False
    // at the start of every Execute iteration so RenderScene's UpdateCamera
    // call knows whether the camera was already updated this frame (e.g. by
    // CheckMousePush's pre-update). Without this, calling UpdateCamera twice
    // per frame would make AutoRotate spin twice as fast.
    FCameraUpdatedThisFrame: Boolean;
    // Set by RecreateEngine from the main thread to signal the worker that
    // it should swap out FGrass for a new engine with FNumBlades blades on
    // the next iteration. We can't free FGrass from the main thread because
    // the worker is actively rendering it - the worker picks up this flag,
    // frees the old engine, creates the new one, and pushes the desired
    // values - all from the safe context of the render thread.
    FNeedsRecreate: Boolean;
    FNumBlades: Integer;
    procedure RenderScene;
    procedure SetActive(const Value: Boolean);
    procedure PushDesiredValuesToEngine;
    procedure UpdateManualCamera;
    procedure UpdateCameraOnce;
    procedure CheckMousePush;
  protected
    procedure Execute; override;
  public
    constructor Create(AParentHandle: HWND; ANumBlades: Integer = DEFAULT_BLADE_COUNT);
    destructor Destroy; override;
    { Recreate the inner grass engine with a new blade count. Stops the
      thread, frees the old engine, creates a new one with the new count,
      pushes the currently-desired parameter values, and re-starts. Called
      by the form when the user picks a new value in the Blade Count combo. }
    procedure RecreateEngine(ANewBladeCount: Integer);
    procedure StartEngine;
    procedure StopEngine;
    procedure Restart;
    procedure Reset;
    { Configuration setters - all live-editable from the VCL form. }
    procedure SetFieldOrigin(X, Y, Z: Single);
    procedure SetFieldSize(AWidth, ADepth: Single);
    procedure SetBladeHeight(H: Single);
    procedure SetBladeWidth(W: Single);
    procedure SetWindDir(X, Y, Z: Single);
    procedure SetWindStrength(S: Single);
    procedure SetWindGustFreq(F: Single);
    procedure SetGrassColors(BaseR, BaseG, BaseB, TipR, TipG, TipB: Single);
    procedure SetColorVariation(V: Single);
    procedure SetHDRMultiplier(M: Single);
    procedure SetParticleScale(S: Single);
    procedure SetBendAmount(B: Single);
    procedure SetPushRadius(R: Single);
    procedure SetPushStrength(S: Single);
    procedure SetFPS(const FPS: Integer);
    procedure SetDimensions(const W, H: Integer);
    procedure SetCamera(const Pos, Target: TVector3; Fovy: Single);
    procedure SetAutoRotate(Value: Boolean);
    property RealFPS: Integer read FRealFPS;
    property TargetFPS: Integer read FTargetFPS;
    property Active: Boolean read FActive write SetActive;
    property GrassEngine: TYutaniGrassEngine read FGrass;
    property AutoRotate: Boolean read FAutoRotate write SetAutoRotate;
  end;

implementation

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

{ TGrasEngine }

constructor TGrasEngine.Create(AParentHandle: HWND; ANumBlades: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FParentHandle := AParentHandle;
  FNumBlades := ANumBlades;
  FTargetFPS := 60;
  FActive := False;
  FWidth := 800;
  FHeight := 800;
  FGrass := nil;

  // Camera tuned for a 20x20 ground patch with 2m-tall blades: closer
  // and lower than the original (15,9,15) so the grass fills the frame
  // and individual blades are visible, not sub-pixel.
  FCamera.position := Vector3Create(12.0, 4.0, 12.0);
  FCamera.target := Vector3Create(0.0, 0.5, 0.0);
  FCamera.up := Vector3Create(0, 1, 0);
  FCamera.fovy := 50.0;
  FCamera.projection := CAMERA_PERSPECTIVE;

  // Default grass configuration - mirrors the engine's own defaults so the
  // first rendered frame is already a complete 20x20 grass field with a
  // gentle breeze. The VCL form can override any of these.
  FDesiredFieldOriginX  := -10.0;
  FDesiredFieldOriginY  :=   0.0;
  FDesiredFieldOriginZ  := -10.0;
  FDesiredFieldWidth    :=  20.0;
  FDesiredFieldDepth    :=  20.0;
  FDesiredBladeHeight   :=   2.0;
  FDesiredBladeWidth    :=   0.06;
  FDesiredWindDirX      :=   1.0;
  FDesiredWindDirY      :=   0.0;
  FDesiredWindDirZ      :=   0.2;
  FDesiredWindStrength  :=   1.5;
  FDesiredWindGustFreq  :=   1.0;
  FDesiredGrassBaseR    :=   0.13;
  FDesiredGrassBaseG    :=   0.34;
  FDesiredGrassBaseB    :=   0.08;
  FDesiredGrassTipR     :=   0.45;
  FDesiredGrassTipG     :=   0.70;
  FDesiredGrassTipB     :=   0.20;
  FDesiredColorVariation :=  0.20;
  FDesiredHDRMultiplier :=   1.0;
  FDesiredParticleScale :=   1.0;
  // Default bendiness: 0.7 = clearly bendy, matches the engine's own default.
  // The user can tune this from the form's "Bend Amount" slider.
  FDesiredBendAmount :=      0.7;
  // Default mouse push: radius 2.2 (covers a small patch), strength 2.5
  // (clearly visible part, not so strong it obliterates the grass).
  // Both are tuneable from the form.
  FDesiredPushRadius :=     2.2;
  FDesiredPushStrength :=   2.5;
  FNeedsRecreate := False;

  FAutoRotate := True;
  FCamYaw   := 0.785;  // 45 degrees
  FCamPitch := 0.35;   // ~20 degrees down - flatter angle so we see the
                       // individual blades against the ground, not just
                       // a top-down sea of green.
  FCamDist  := 16.0;  // distance to target - tight enough that the
                       // 20x20 patch + 2m blades fill the view.
end;

destructor TGrasEngine.Destroy;
begin
  StopEngine;
  if Assigned(FGrass) then
    FreeAndNil(FGrass);
  inherited;
end;

procedure TGrasEngine.RecreateEngine(ANewBladeCount: Integer);
{ Thread-safe engine swap. The main thread calls this with the new blade
  count; it just stores FNumBlades and sets FNeedsRecreate. The worker
  thread picks up the flag at the top of its main loop (BEFORE any
  FGrass.Update / FGrass.Render call this frame), frees the old engine,
  creates the new one with the new blade count, calls Initialise, and
  pushes the desired values - all from the worker thread where FGrass
  is safely owned. }
begin
  FNumBlades := ANewBladeCount;
  FNeedsRecreate := True;
end;

procedure TGrasEngine.SetDimensions(const W, H: Integer);
begin
  FWidth := W;
  FHeight := H;
  if FRaylibWnd <> 0 then
    SetWindowPos(FRaylibWnd, 0, 0, 0, FWidth, FHeight, SWP_NOZORDER or SWP_NOACTIVATE);
end;

procedure TGrasEngine.SetActive(const Value: Boolean);
begin
  if FActive <> Value then
  begin
    FActive := Value;
    if FActive and Suspended then
      Start;
  end;
end;

procedure TGrasEngine.StartEngine;
begin
  Active := True;
end;

procedure TGrasEngine.StopEngine;
begin
  Active := False;
end;

procedure TGrasEngine.SetFPS(const FPS: Integer);
begin
  if FTargetFPS <> FPS then
    FTargetFPS := FPS;
end;

procedure TGrasEngine.SetCamera(const Pos, Target: TVector3; Fovy: Single);
begin
  FCamera.position := Pos;
  FCamera.target := Target;
  FCamera.fovy := Fovy;
end;

procedure TGrasEngine.SetAutoRotate(Value: Boolean);
begin
  FAutoRotate := Value;
end;

{ UpdateManualCamera reads WASD/arrow keys + middle-mouse-drag from Raylib
  and moves/orbits the camera manually. Called instead of UpdateCamera
  (CAMERA_ORBITAL) when AutoRotate is False. Mouse must be inside the
  Raylib window, otherwise VCL controls need the keystrokes. }
procedure TGrasEngine.UpdateCameraOnce;
{ Single per-frame camera update. Idempotent via FCameraUpdatedThisFrame:
  the first call this frame does the actual update (AutoRotate or manual),
  subsequent calls are no-ops. This lets CheckMousePush update the camera
  before computing the push ray (so it uses the current frame's camera
  state, not the previous frame's) without RenderScene double-applying the
  rotation when it later renders. }
begin
  if FCameraUpdatedThisFrame then Exit;
  if FAutoRotate then
    UpdateCamera(@FCamera, CAMERA_ORBITAL)
  else
    UpdateManualCamera;
  FCameraUpdatedThisFrame := True;
end;

procedure TGrasEngine.UpdateManualCamera;
var
  Fwd, Right, RealUp: TVector3;
  Speed: Single;
  DX, DY: Single;
  MouseX, MouseY: Integer;
begin
  MouseX := GetMouseX;
  MouseY := GetMouseY;
  if (MouseX < 0) or (MouseX >= FWidth) or (MouseY < 0) or (MouseY >= FHeight) then
    Exit;
  // Build camera basis vectors
  Fwd.x := FCamera.target.x - FCamera.position.x;
  Fwd.y := FCamera.target.y - FCamera.position.y;
  Fwd.z := FCamera.target.z - FCamera.position.z;
  Fwd := Vector3Normalize(Fwd);
  Right := Vector3CrossProduct(Fwd, FCamera.up);
  Right := Vector3Normalize(Right);
  RealUp := Vector3CrossProduct(Right, Fwd);

  Speed := 0.4;

  if IsKeyDown(KEY_UP) or IsKeyDown(KEY_W) then
  begin
    FCamera.position := Vector3Add(FCamera.position, Vector3Scale(Fwd, Speed));
    FCamera.target := Vector3Add(FCamera.target, Vector3Scale(Fwd, Speed));
  end;
  if IsKeyDown(KEY_DOWN) or IsKeyDown(KEY_S) then
  begin
    FCamera.position := Vector3Subtract(FCamera.position, Vector3Scale(Fwd, Speed));
    FCamera.target := Vector3Subtract(FCamera.target, Vector3Scale(Fwd, Speed));
  end;
  if IsKeyDown(KEY_LEFT) or IsKeyDown(KEY_A) then
  begin
    FCamera.position := Vector3Subtract(FCamera.position, Vector3Scale(Right, Speed));
    FCamera.target := Vector3Subtract(FCamera.target, Vector3Scale(Right, Speed));
  end;
  if IsKeyDown(KEY_RIGHT) or IsKeyDown(KEY_D) then
  begin
    FCamera.position := Vector3Add(FCamera.position, Vector3Scale(Right, Speed));
    FCamera.target := Vector3Add(FCamera.target, Vector3Scale(Right, Speed));
  end;

  // Middle mouse drag = orbit around target (yaw + pitch)
  if IsMouseButtonDown(MOUSE_MIDDLE_BUTTON) then
  begin
    DX := GetMouseDelta().x;
    DY := GetMouseDelta().y;
    FCamYaw := FCamYaw - DX * 0.008;
    FCamPitch := FCamPitch + DY * 0.008;
    if FCamPitch > 1.5 then FCamPitch := 1.5;
    if FCamPitch < -1.5 then FCamPitch := -1.5;
    FCamera.position.x := FCamera.target.x + FCamDist * Cos(FCamPitch) * Sin(FCamYaw);
    FCamera.position.y := FCamera.target.y + FCamDist * Sin(FCamPitch);
    FCamera.position.z := FCamera.target.z + FCamDist * Cos(FCamPitch) * Cos(FCamYaw);
  end;

  // Mouse wheel = zoom
  if GetMouseWheelMove() <> 0 then
  begin
    FCamDist := FCamDist - GetMouseWheelMove() * 1.5;
    if FCamDist < 3.0 then FCamDist := 3.0;
    if FCamDist > 80.0 then FCamDist := 80.0;
    FCamera.position.x := FCamera.target.x + FCamDist * Cos(FCamPitch) * Sin(FCamYaw);
    FCamera.position.y := FCamera.target.y + FCamDist * Sin(FCamPitch);
    FCamera.position.z := FCamera.target.z + FCamDist * Cos(FCamPitch) * Cos(FCamYaw);
  end;
end;

{ ============================================================================
  CheckMousePush - reads the Raylib mouse state and converts screen-space
  mouse position to a world-space push point on the ground plane
  (Y = FDesiredFieldOriginY) via manual camera-vector math. When the
  left mouse button is held inside the Raylib window, the grass under
  the cursor gets pushed away. Same approach as uParticleEngine.pas's
  CheckMousePush, except we intersect with the ground plane instead of
  with the camera-target depth sphere.
  ============================================================================ }

procedure TGrasEngine.CheckMousePush;
var
  MX, MY, SW, SH: Integer;
  Eye, Target, Up, Fwd, Right, RealUp: TVector3;
  NdcX, NdcY, TanFovy, Aspect: Single;
  RayDir, HitPoint: TVector3;
  GroundY, T: Single;
begin
  if not Assigned(FGrass) then Exit;
  if not IsMouseButtonDown(MOUSE_LEFT_BUTTON) then
  begin
    FGrass.ClearPush;
    Exit;
  end;
  MX := GetMouseX;
  MY := GetMouseY;
  // IMPORTANT: use Raylib's own GetScreenWidth()/GetScreenHeight() here,
  // NOT the wrapper's FWidth/FHeight. The VCL form sets FWidth/FHeight via
  // SetDimensions, but if the Raylib window was internally resized by the
  // OS or HiDPI scaling, FWidth/FHeight can differ from the actual drawing
  // surface dimensions. GetMouseX/GetMouseY are relative to the actual
  // drawing surface, so NDC and aspect must use the same coordinate space
  // or the horizontal hit position drifts away from the cursor (the
  // "push point is further back than the cursor" bug).
  SW := GetScreenWidth;
  SH := GetScreenHeight;
  if SW <= 0 then SW := 1;
  if SH <= 0 then SH := 1;
  // Skip if mouse is outside the Raylib window (then VCL controls need it).
  if (MX < 0) or (MX >= SW) or (MY < 0) or (MY >= SH) then
  begin
    FGrass.ClearPush;
    Exit;
  end;
  Eye := FCamera.position;
  Target := FCamera.target;
  Up := FCamera.up;
  // Forward = normalize(Target - Eye)
  Fwd.x := Target.x - Eye.x;
  Fwd.y := Target.y - Eye.y;
  Fwd.z := Target.z - Eye.z;
  T := Sqrt(Fwd.x*Fwd.x + Fwd.y*Fwd.y + Fwd.z*Fwd.z);
  if T > 0.001 then
  begin
    Fwd.x := Fwd.x / T; Fwd.y := Fwd.y / T; Fwd.z := Fwd.z / T;
  end;
  // Right = normalize(cross(Fwd, Up))
  Right.x := Fwd.y * Up.z - Fwd.z * Up.y;
  Right.y := Fwd.z * Up.x - Fwd.x * Up.z;
  Right.z := Fwd.x * Up.y - Fwd.y * Up.x;
  T := Sqrt(Right.x*Right.x + Right.y*Right.y + Right.z*Right.z);
  if T > 0.001 then
  begin
    Right.x := Right.x / T; Right.y := Right.y / T; Right.z := Right.z / T;
  end;
  // RealUp = cross(Right, Fwd)
  RealUp.x := Right.y * Fwd.z - Right.z * Fwd.y;
  RealUp.y := Right.z * Fwd.x - Right.x * Fwd.z;
  RealUp.z := Right.x * Fwd.y - Right.y * Fwd.x;
  // Normalized Device Coordinates from mouse position.
  NdcX := (2.0 * MX / SW) - 1.0;
  NdcY := 1.0 - (2.0 * MY / SH);
  // FOV-based projection: tan(fovy/2) gives the half-height of the view
  // frustum at distance 1 from the camera. Multiply by Aspect for width.
  TanFovy := System.Math.Tan(FCamera.fovy * 0.5 * Pi / 180.0);
  Aspect := SW / SH;
  // Build the ray direction in world space:
  //   rayDir = Fwd + Right * NdcX * TanFovy * Aspect + RealUp * NdcY * TanFovy
  RayDir.x := Fwd.x + Right.x * NdcX * TanFovy * Aspect + RealUp.x * NdcY * TanFovy;
  RayDir.y := Fwd.y + Right.y * NdcX * TanFovy * Aspect + RealUp.y * NdcY * TanFovy;
  RayDir.z := Fwd.z + Right.z * NdcX * TanFovy * Aspect + RealUp.z * NdcY * TanFovy;
  // Intersect with the horizontal ground plane Y = FDesiredFieldOriginY.
  // Plane: y = GroundY. Ray: P = Eye + t * RayDir.
  //   => Eye.y + t * RayDir.y = GroundY
  //   => t = (GroundY - Eye.y) / RayDir.y
  GroundY := FDesiredFieldOriginY;
  if Abs(RayDir.y) < 0.0001 then
  begin
    // Ray nearly parallel to ground - no intersection.
    FGrass.ClearPush;
    Exit;
  end;
  T := (GroundY - Eye.y) / RayDir.y;
  if T <= 0 then
  begin
    // Hit point is behind the camera (we're looking up at the sky).
    FGrass.ClearPush;
    Exit;
  end;
  HitPoint.x := Eye.x + RayDir.x * T;
  HitPoint.y := GroundY;
  HitPoint.z := Eye.z + RayDir.z * T;
  FGrass.SetPush(HitPoint, FDesiredPushRadius, FDesiredPushStrength);
end;

{ ============================================================================
  Push desired parameter values to the freshly-created engine.
  Called from Execute after FGrass.Initialise succeeds.
  ============================================================================ }

procedure TGrasEngine.PushDesiredValuesToEngine;
begin
  if not Assigned(FGrass) then Exit;
  FGrass.SetFieldOrigin(FDesiredFieldOriginX, FDesiredFieldOriginY, FDesiredFieldOriginZ);
  FGrass.SetFieldSize(FDesiredFieldWidth, FDesiredFieldDepth);
  FGrass.SetBladeHeight(FDesiredBladeHeight);
  FGrass.SetBladeWidth(FDesiredBladeWidth);
  FGrass.SetWindDir(FDesiredWindDirX, FDesiredWindDirY, FDesiredWindDirZ);
  FGrass.SetWindStrength(FDesiredWindStrength);
  FGrass.SetWindGustFreq(FDesiredWindGustFreq);
  FGrass.SetGrassColors(
    FDesiredGrassBaseR, FDesiredGrassBaseG, FDesiredGrassBaseB,
    FDesiredGrassTipR,  FDesiredGrassTipG,  FDesiredGrassTipB);
  FGrass.SetColorVariation(FDesiredColorVariation);
  FGrass.SetHDRMultiplier(FDesiredHDRMultiplier);
  FGrass.SetParticleScale(FDesiredParticleScale);
  FGrass.SetBendAmount(FDesiredBendAmount);
end;

{ ============================================================================
  Simulation control
  ============================================================================ }

procedure TGrasEngine.Restart;
begin
  if Assigned(FGrass) then
    FGrass.Reset;
end;

procedure TGrasEngine.Reset;
begin
  // Reset desired values to the engine defaults AND push them live.
  FDesiredFieldOriginX  := -10.0;
  FDesiredFieldOriginY  :=   0.0;
  FDesiredFieldOriginZ  := -10.0;
  FDesiredFieldWidth    :=  20.0;
  FDesiredFieldDepth    :=  20.0;
  FDesiredBladeHeight   :=   2.0;
  FDesiredBladeWidth    :=   0.06;
  FDesiredWindDirX      :=   1.0;
  FDesiredWindDirY      :=   0.0;
  FDesiredWindDirZ      :=   0.2;
  FDesiredWindStrength  :=   1.5;
  FDesiredWindGustFreq  :=   1.0;
  FDesiredGrassBaseR    :=   0.13;
  FDesiredGrassBaseG    :=   0.34;
  FDesiredGrassBaseB    :=   0.08;
  FDesiredGrassTipR     :=   0.45;
  FDesiredGrassTipG     :=   0.70;
  FDesiredGrassTipB     :=   0.20;
  FDesiredColorVariation :=  0.20;
  FDesiredHDRMultiplier :=   1.0;
  FDesiredParticleScale :=   1.0;
  FDesiredBendAmount :=      0.7;
  FDesiredPushRadius :=     2.2;
  FDesiredPushStrength :=   2.5;
  if Assigned(FGrass) then
    FGrass.Reset;
  // Push the freshly-reset desired values live to the engine. Without this,
  // Reset only updates the FDesiredXxx fields and the engine keeps rendering
  // with whatever was pushed last - so clicking Reset had no visible effect
  // until the user touched another slider. PushDesiredValuesToEngine forwards
  // every FDesiredXxx to the matching FGrass.SetXxx in one shot.
  PushDesiredValuesToEngine;
end;

{ ============================================================================
  Parameter setters - store desired value AND push to live engine if ready.
  ============================================================================ }

procedure TGrasEngine.SetFieldOrigin(X, Y, Z: Single);
begin
  FDesiredFieldOriginX := X;
  FDesiredFieldOriginY := Y;
  FDesiredFieldOriginZ := Z;
  if Assigned(FGrass) then
    FGrass.SetFieldOrigin(X, Y, Z);
end;

procedure TGrasEngine.SetFieldSize(AWidth, ADepth: Single);
begin
  FDesiredFieldWidth := AWidth;
  FDesiredFieldDepth := ADepth;
  if Assigned(FGrass) then
    FGrass.SetFieldSize(AWidth, ADepth);
end;

procedure TGrasEngine.SetBladeHeight(H: Single);
begin
  FDesiredBladeHeight := H;
  if Assigned(FGrass) then
    FGrass.SetBladeHeight(H);
end;

procedure TGrasEngine.SetBladeWidth(W: Single);
begin
  FDesiredBladeWidth := W;
  if Assigned(FGrass) then
    FGrass.SetBladeWidth(W);
end;

procedure TGrasEngine.SetWindDir(X, Y, Z: Single);
begin
  FDesiredWindDirX := X;
  FDesiredWindDirY := Y;
  FDesiredWindDirZ := Z;
  if Assigned(FGrass) then
    FGrass.SetWindDir(X, Y, Z);
end;

procedure TGrasEngine.SetWindStrength(S: Single);
begin
  FDesiredWindStrength := S;
  if Assigned(FGrass) then
    FGrass.SetWindStrength(S);
end;

procedure TGrasEngine.SetWindGustFreq(F: Single);
begin
  FDesiredWindGustFreq := F;
  if Assigned(FGrass) then
    FGrass.SetWindGustFreq(F);
end;

procedure TGrasEngine.SetGrassColors(BaseR, BaseG, BaseB, TipR, TipG, TipB: Single);
begin
  FDesiredGrassBaseR := BaseR;
  FDesiredGrassBaseG := BaseG;
  FDesiredGrassBaseB := BaseB;
  FDesiredGrassTipR := TipR;
  FDesiredGrassTipG := TipG;
  FDesiredGrassTipB := TipB;
  if Assigned(FGrass) then
    FGrass.SetGrassColors(BaseR, BaseG, BaseB, TipR, TipG, TipB);
end;

procedure TGrasEngine.SetColorVariation(V: Single);
begin
  FDesiredColorVariation := V;
  if Assigned(FGrass) then
    FGrass.SetColorVariation(V);
end;

procedure TGrasEngine.SetHDRMultiplier(M: Single);
begin
  FDesiredHDRMultiplier := M;
  if Assigned(FGrass) then
    FGrass.SetHDRMultiplier(M);
end;

procedure TGrasEngine.SetParticleScale(S: Single);
begin
  FDesiredParticleScale := S;
  if Assigned(FGrass) then
    FGrass.SetParticleScale(S);
end;

procedure TGrasEngine.SetBendAmount(B: Single);
begin
  FDesiredBendAmount := B;
  if Assigned(FGrass) then
    FGrass.SetBendAmount(B);
end;

procedure TGrasEngine.SetPushRadius(R: Single);
begin
  FDesiredPushRadius := R;
  // Don't forward to FGrass here - the live engine gets the push radius
  // every frame via CheckMousePush -> FGrass.SetPush(...) when the user
  // is actively dragging. The radius is also stored on the engine if the
  // user happens to drag during the next frame.
end;

procedure TGrasEngine.SetPushStrength(S: Single);
begin
  FDesiredPushStrength := S;
end;

procedure TGrasEngine.RenderScene;
var
  PlaneCenter: TVector3;
  PlaneSize: TVector2;
begin
  BeginDrawing();
  // Pure black background - requested by the user, lets the green grass
  // pop without the dark-gray haze of the previous DARKGRAY background.
  ClearBackground(BLACK);

  // Camera: auto-rotate (orbit) or manual (WASD/arrows + middle-mouse
  // drag + wheel zoom). Idempotent - if CheckMousePush already updated
  // the camera this frame (to use the current frame's camera state for
  // its ground-plane ray intersection), this call is a no-op. Without
  // this guard we'd double-apply the orbital rotation each frame.
  UpdateCameraOnce;

  rlEnableDepthTest();
  rlDisableBackfaceCulling();
  BeginMode3D(FCamera);
  try
    // Ground plane: centered on the field's XZ center (origin is at one
    // corner of the field), sized to cover the field + 4m margin so the
    // grass never appears to hover outside the ground when the user moves
    // the field via Field Origin or resizes it via Width/Depth.
    PlaneCenter := Vector3Create(
      FDesiredFieldOriginX + FDesiredFieldWidth * 0.5,
      FDesiredFieldOriginY,
      FDesiredFieldOriginZ + FDesiredFieldDepth * 0.5);
    PlaneSize := Vector2Create(FDesiredFieldWidth + 4.0, FDesiredFieldDepth + 4.0);
    DrawPlane(PlaneCenter, PlaneSize, ColorCreate(40, 50, 30, 255));
    if Assigned(FGrass) then
      FGrass.Render(FCamera);
  finally
    EndMode3D();
  end;

  rlEnableBackfaceCulling();
  rlDisableDepthTest();

  // ========================================================================
  // NOTE: same caveat as uParticleEngine - we do NOT call DrawText() here.
  // The GPU grass engine leaves OpenGL state in a custom configuration
  // (raw GL shaders bound, SSBOs on slots 0..1). Raylib's DrawText would
  // occasionally render as solid blocks because the font atlas binding
  // gets out of sync between our raw-GL pass and Raylib's text batching.
  // FPS + blade count are shown as VCL labels in the form, independent
  // of the Raylib render window.
  // ========================================================================

  EndDrawing();

  if FRaylibWnd <> 0 then
    RedrawWindow(FRaylibWnd, nil, 0, RDW_INVALIDATE or RDW_UPDATENOW);
end;

procedure TGrasEngine.Execute;
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
    SetConfigFlags(FLAG_MSAA_4X_HINT);
    WindowName := AnsiString('GrasEngine_' + IntToStr(IntPtr(Self)));
    InitWindow(FWidth, FHeight, PAnsiChar(WindowName));

    FRaylibWnd := FindWindowA(nil, PAnsiChar(WindowName));
    if (FRaylibWnd <> 0) and (FParentHandle <> 0) then
    begin
      Winapi.Windows.SetParent(FRaylibWnd, FParentHandle);
      SetWindowLong(FRaylibWnd, GWL_STYLE, WS_CHILD or WS_VISIBLE);
      SetWindowPos(FRaylibWnd, 0, 0, 0, FWidth, FHeight, SWP_NOZORDER or SWP_NOACTIVATE);
    end;

    // Create + initialise the compute-shader grass engine HERE.
    FGrass := TYutaniGrassEngine.Create(FNumBlades);
    FGrass.Initialise;

    // Push the currently-desired parameter values to the fresh engine.
    PushDesiredValuesToEngine;

    // Initialize frame pacing timers
    Timer.Init;
    Freq := Timer.Frequency;
    if Freq <= 0 then Freq := 10000000;
    NowTicks := Timer.GetTicks;
    LastFrameTicks := NowTicks;
    NextFrame := NowTicks;
    LastFpsTime := NowTicks;
    FrameCount := 0;

    while not Terminated do
    begin
      if WindowShouldClose() then Break;

      // === Recreate check ===
      // Set by RecreateEngine from the main thread when the user picks a
      // new blade count in the form's combo. Handle it here, at the top of
      // the loop, BEFORE we touch FGrass this frame - this is the only
      // place where it is safe to free + recreate FGrass, because we are
      // in the worker thread that owns FGrass.
      if FNeedsRecreate then
      begin
        FNeedsRecreate := False;
        if Assigned(FGrass) then
          FreeAndNil(FGrass);
        FGrass := TYutaniGrassEngine.Create(FNumBlades);
        FGrass.Initialise;
        PushDesiredValuesToEngine;
        // Force a fresh frame time on the next iteration so the spring-back
        // mix doesn't see a huge deltaTime gap (which would make all the
        // grass snap to its new target instantly instead of easing).
        LastFrameTicks := Timer.GetTicks;
      end;

      NowTicks := Timer.GetTicks;
      DeltaSec := (NowTicks - LastFrameTicks) / Freq;
      LastFrameTicks := NowTicks;

      if (DeltaSec <= 0) or (DeltaSec > 0.25) then
        DeltaSec := 1 / 60;

      if FActive then
      begin
        // CRITICAL ordering for accurate mouse push:
        //   1. Reset FCameraUpdatedThisFrame so UpdateCameraOnce will do
        //      the actual update this frame.
        //   2. Update the camera BEFORE CheckMousePush so CheckMousePush
        //      sees the CURRENT frame's camera state, not the previous
        //      frame's. With AutoRotate ON, the camera moves every frame,
        //      so using last frame's camera state for the ground-plane
        //      ray intersection produces a visible lag/offset between
        //      the cursor and the grass-parting point.
        //   3. CheckMousePush uses the now-current FCamera to compute the
        //      ground hit point and forwards it to FGrass.SetPush.
        //   4. RenderScene's UpdateCameraOnce call is then a no-op (the
        //      flag is already set) so AutoRotate doesn't rotate twice.
        FCameraUpdatedThisFrame := False;
        UpdateCameraOnce;
        CheckMousePush;
        if Assigned(FGrass) then
          FGrass.Update(DeltaSec);
      end
      else
        FCameraUpdatedThisFrame := False;
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
    FreeAndNil(FGrass);
    if FRaylibWnd <> 0 then
      CloseWindow();
    {$IFDEF MSWINDOWS}
    timeEndPeriod(1);
    {$ENDIF}
  end;
end;

end.
